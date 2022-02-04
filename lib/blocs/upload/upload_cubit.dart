import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/blocs/upload/multi_file_upload_handle.dart';
import 'package:ardrive/blocs/upload/upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:file_picker/file_picker.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pedantic/pedantic.dart';
import 'package:uuid/uuid.dart';

import '../blocs.dart';
import 'file_upload_handle.dart';

part 'upload_state.dart';

final bundleSizeLimit = 503316480;
final maxBundleDataItemCount = 500;
final maxFilesPerBundle = maxBundleDataItemCount ~/ 2;
final privateFileSizeLimit = 104857600;
final minimumPstTip = BigInt.from(10000000);

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final List<PlatformFile> files;

  final _uuid = Uuid();
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final PstService _pst;

  late Drive _targetDrive;
  late FolderEntry _targetFolder;

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};

  /// A map of [FileUploadHandle]s keyed by their respective file's id.
  final Map<String, FileUploadHandle> _fileUploadHandles = {};
  final Map<String, FileUploadHandle> _dataItemUploadHandles = {};

  /// A list of all multi file upload handles containing bundles of multiple files
  final List<MultiFileUploadHandle> _multiFileUploadHandles = [];

  /// The [Transaction] that pays `pstFee` to a random PST holder. (Only for v2 transaction uploads)
  Transaction? feeTx;

  bool fileSizeWithinBundleLimits(int size) => size < bundleSizeLimit;

  UploadCubit({
    required this.driveId,
    required this.folderId,
    required this.files,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required PstService pst,
  })  : _profileCubit = profileCubit,
        _driveDao = driveDao,
        _arweave = arweave,
        _pst = pst,
        super(UploadPreparationInProgress()) {
    () async {
      _targetDrive = await _driveDao.driveById(driveId: driveId).getSingle();
      _targetFolder = await _driveDao
          .folderById(driveId: driveId, folderId: folderId)
          .getSingle();

      unawaited(checkConflictingFiles());
    }();
  }

  /// Tries to find a files that conflict with the files in the target folder.
  ///
  /// If there's one, prompt the user to upload the file as a version of the existing one.
  /// If there isn't one, prepare to upload the file.
  Future<void> checkConflictingFiles() async {
    emit(UploadPreparationInProgress());

    for (final file in files) {
      final fileName = file.name;
      final existingFileId = await _driveDao
          .filesInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: _targetFolder.id,
            name: fileName,
          )
          .map((f) => f.id)
          .getSingleOrNull();

      if (existingFileId != null) {
        conflictingFiles[fileName] = existingFileId;
      }
    }

    if (conflictingFiles.isNotEmpty) {
      emit(UploadFileConflict(
          conflictingFileNames: conflictingFiles.keys.toList()));
    } else {
      unawaited(prepareUpload());
    }
  }

  Future<void> prepareUpload() async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final packageInfo = await PackageInfo.fromPlatform();

    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }

    emit(
      UploadPreparationInProgress(
        isArConnect: await _profileCubit.isCurrentProfileArConnect(),
      ),
    );
    final sizeLimit = (_targetDrive.isPrivate
        ? privateFileSizeLimit
        : 1.25 * math.pow(10, 9)) as int;
    final tooLargeFiles = [
      for (final file in files)
        if (file.size > sizeLimit) file.name
    ];

    if (tooLargeFiles.isNotEmpty) {
      emit(UploadFileTooLarge(
        tooLargeFileNames: tooLargeFiles,
        isPrivate: _targetDrive.isPrivate,
      ));
      return;
    }

    try {
      for (final file in files) {
        final uploadHandle = await prepareFileUpload(file);
        if (uploadHandle.entityTx is DataItem &&
            uploadHandle.dataTx is DataItem) {
          _dataItemUploadHandles[uploadHandle.entity.id!] = uploadHandle;
        } else {
          _fileUploadHandles[uploadHandle.entity.id!] = uploadHandle;
        }
      }
    } catch (err) {
      addError(err);
      return;
    }
    final dataItemsCost = _dataItemUploadHandles.isNotEmpty
        ? await estimateBundleCosts(_dataItemUploadHandles.values.toList())
        : BigInt.zero;
    final uploadCost = _fileUploadHandles.isNotEmpty
        ? _fileUploadHandles.values
            .map((e) => e.cost)
            .reduce((value, element) => value += element)
        : BigInt.zero;

    var pstFee = await getPSTFee(uploadCost);
    final bundlePstFee = await getPSTFee(dataItemsCost);
    if (pstFee > BigInt.zero) {
      feeTx = await _arweave.client.transactions.prepare(
        Transaction(
          target: await _pst.getWeightedPstHolder(),
          quantity: pstFee,
        ),
        profile.wallet,
      )
        ..addApplicationTags(version: packageInfo.version)
        ..addTag('Type', 'fee')
        ..addTag(TipType.tagName, TipType.dataUpload);
      await feeTx!.sign(profile.wallet);
    }

    if (_fileUploadHandles.isNotEmpty) {
      pstFee = pstFee > minimumPstTip ? pstFee : minimumPstTip;
    }

    final totalCost = uploadCost + dataItemsCost + pstFee + bundlePstFee;

    final arUploadCost = winstonToAr(totalCost);
    final usdUploadCost = await _arweave
        .getArUsdConversionRate()
        .then((conversionRate) => double.parse(arUploadCost) * conversionRate);
    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }
    emit(
      UploadReady(
        arUploadCost: arUploadCost,
        usdUploadCost: usdUploadCost,
        pstFee: pstFee,
        totalCost: totalCost,
        uploadIsPublic: _targetDrive.isPublic,
        sufficientArBalance: profile.walletBalance >= totalCost,
        files: _fileUploadHandles.values.toList() +
            _dataItemUploadHandles.values.toList(),
        bundles: _multiFileUploadHandles,
      ),
    );
  }

  Future<BigInt> getPSTFee(BigInt uploadCost) async {
    return await _pst
        .getPstFeePercentage()
        .then((feePercentage) =>
            // Workaround [BigInt] percentage division problems
            // by first multiplying by the percentage * 100 and then dividing by 100.
            uploadCost * BigInt.from(feePercentage * 100) ~/ BigInt.from(100))
        .catchError((_) => BigInt.zero,
            test: (err) => err is UnimplementedError);
  }

  Future<BigInt> estimateBundleCosts(List<FileUploadHandle> files) async {
    // https://github.com/joshbenaron/arweave-standards/blob/ans104/ans/ANS-104.md
    // NOTE: Using maxFilesPerBundle since FileUploadHandles have 2 data items
    final bundleList = await NextFitBundlePacker<FileUploadHandle>(
      maxBundleSize: bundleSizeLimit,
      maxDataItemCount: maxFilesPerBundle,
    ).packItems(files);

    var totalCost = BigInt.zero;
    for (var bundle in bundleList) {
      final fileSizes = bundle.map((e) =>
          (e.dataTx as DataItem).getSize() +
          (e.entityTx as DataItem).getSize());
      var size = 0;
      // Add data item binary size
      size += fileSizes.reduce((value, element) => value + element);
      // Add data item offset and entry id for each data item
      size += (fileSizes.length * 64);
      // Add bytes that denote number of data items
      size += 32;

      totalCost += await _arweave.getPrice(byteSize: size);
    }

    return totalCost;
  }

  Future<void> startUpload() async {
    final profile = _profileCubit.state as ProfileLoggedIn;

    //Check if the same wallet it being used before starting upload.
    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }
    if (_dataItemUploadHandles.isNotEmpty) {
      emit(
        UploadBundlingInProgress(
          isArConnect: await _profileCubit.isCurrentProfileArConnect(),
        ),
      );
    }

    if (feeTx != null && _fileUploadHandles.isNotEmpty) {
      await _arweave.postTx(feeTx!);
    }
    await _driveDao.transaction(() async {
      // NOTE: Using maxFilesPerBundle since FileUploadHandles have 2 data items
      final bundleItems = await NextFitBundlePacker<FileUploadHandle>(
        maxBundleSize: bundleSizeLimit,
        maxDataItemCount: maxFilesPerBundle,
      ).packItems(_dataItemUploadHandles.values.toList());

      //Create bundles
      for (var uploadHandles in bundleItems) {
        final dataBundle = DataBundle(
          items: uploadHandles
              .map((e) => e.asDataItems().toList())
              .reduce((value, element) => value += element)
              .toList(),
        );

        // Create bundle tx
        final bundleTx =
            await _arweave.prepareDataBundleTx(dataBundle, profile.wallet);

        // Add tips to bundle tx
        final bundleTip = await getPSTFee(bundleTx.reward);
        bundleTx
          ..addTag(TipType.tagName, TipType.dataUpload)
          ..setTarget(await _pst.getWeightedPstHolder())
          ..setQuantity(bundleTip);

        await bundleTx.sign(profile.wallet);

        var uploadSize = 0;
        for (var uploadHandle in uploadHandles) {
          final fileEntity = uploadHandle.entity;
          if (uploadHandle.entityTx?.id != null) {
            fileEntity.txId = uploadHandle.entityTx!.id;
          }

          fileEntity.bundledIn = bundleTx.id;

          await _driveDao.writeFileEntity(fileEntity, uploadHandle.path);
          await _driveDao.insertFileRevision(
            fileEntity.toRevisionCompanion(
              performedAction: !conflictingFiles.containsKey(fileEntity.name)
                  ? RevisionAction.create
                  : RevisionAction.uploadNewVersion,
            ),
          );

          assert(uploadHandle.entity.dataTxId == uploadHandle.dataTx!.id);
          uploadSize += uploadHandle.entity.size!;
        }

        _multiFileUploadHandles.add(
          MultiFileUploadHandle(
            bundleTx,
            uploadSize,
            uploadHandles.map((e) => e.entity).toList(),
          ),
        );
        uploadHandles.clear();
      }

      emit(UploadInProgress(
        files: List<UploadHandle>.from(_fileUploadHandles.values.toList()) +
            _multiFileUploadHandles,
      ));
      for (var uploadHandle in _multiFileUploadHandles) {
        await for (final _ in uploadHandle.upload(_arweave)) {
          emit(UploadInProgress(
            files: List<UploadHandle>.from(_fileUploadHandles.values.toList()) +
                _multiFileUploadHandles,
          ));
        }
      }
      for (final uploadHandle in _fileUploadHandles.values) {
        final fileEntity = uploadHandle.entity;
        if (uploadHandle.entityTx?.id != null) {
          fileEntity.txId = uploadHandle.entityTx!.id;
        }

        await _driveDao.writeFileEntity(fileEntity, uploadHandle.path);
        await _driveDao.insertFileRevision(
          fileEntity.toRevisionCompanion(
            performedAction: !conflictingFiles.containsKey(fileEntity.name)
                ? RevisionAction.create
                : RevisionAction.uploadNewVersion,
          ),
        );
        await for (final _ in uploadHandle.upload(_arweave)) {
          emit(UploadInProgress(
            files: List<UploadHandle>.from(_fileUploadHandles.values.toList()) +
                _multiFileUploadHandles,
          ));
        }
      }
    });

    unawaited(_profileCubit.refreshBalance());

    emit(UploadComplete());
  }

  Future<FileUploadHandle> prepareFileUpload(PlatformFile file) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    final packageInfo = await PackageInfo.fromPlatform();

    final fileName = file.name;
    final filePath = '${_targetFolder.path}/$fileName';
    final fileEntity = FileEntity(
      driveId: _targetDrive.id,
      name: fileName,
      size: file.size,
      lastModifiedDate: DateTime.now(),
      parentFolderId: _targetFolder.id,
      dataContentType: lookupMimeType(fileName) ?? 'application/octet-stream',
    );

    // If this file conflicts with one that already exists in the target folder reuse the id of the conflicting file.
    fileEntity.id = conflictingFiles[fileName] ?? _uuid.v4();

    final private = _targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(_targetDrive.id, profile.cipherKey)
        : null;
    final fileKey =
        private ? await deriveFileKey(driveKey!, fileEntity.id!) : null;

    final fileData = file.bytes!;

    final uploadHandle = FileUploadHandle(entity: fileEntity, path: filePath);
    if (fileSizeWithinBundleLimits(fileData.length)) {
      uploadHandle.dataTx = private
          ? await createEncryptedDataItem(fileData, fileKey!)
          : DataItem.withBlobData(data: fileData);
      uploadHandle.dataTx!.setOwner(await profile.wallet.getOwner());
    } else {
      uploadHandle.dataTx = await _arweave.client.transactions.prepare(
        private
            ? await createEncryptedTransaction(fileData, fileKey!)
            : Transaction.withBlobData(data: fileData),
        profile.wallet,
      );
    }

    uploadHandle.dataTx!.addApplicationTags(version: packageInfo.version);

    // Don't include the file's Content-Type tag if it is meant to be private.
    if (!private) {
      uploadHandle.dataTx!.addTag(
        EntityTag.contentType,
        fileEntity.dataContentType!,
      );
    }

    await uploadHandle.dataTx!.sign(profile.wallet);

    fileEntity.dataTxId = uploadHandle.dataTx!.id;

    if (fileSizeWithinBundleLimits(fileData.length)) {
      uploadHandle.entityTx = await _arweave.prepareEntityDataItem(
          fileEntity, profile.wallet, fileKey);
      final entityDataItem = (uploadHandle.entityTx as DataItem?)!;
      final dataDataItem = (uploadHandle.dataTx as DataItem?)!;

      await entityDataItem.sign(profile.wallet);
      await dataDataItem.sign(profile.wallet);
    } else {
      uploadHandle.entityTx =
          await _arweave.prepareEntityTx(fileEntity, profile.wallet, fileKey);
    }

    return uploadHandle;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(UploadFailure());
    super.onError(error, stackTrace);

    print('Failed to upload file: $error $stackTrace');
  }
}
