import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:meta/meta.dart';
import 'package:mime/mime.dart';
import 'package:pedantic/pedantic.dart';
import 'package:uuid/uuid.dart';

import '../blocs.dart';
import 'file_upload_handle.dart';

part 'upload_state.dart';

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String folderId;
  final List<XFile> files;

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

  /// The [Transaction] that pays `pstFee` to a random PST holder.
  Transaction? feeTx;

  final bundleSizeLimit = 503316480;
  final privateFileSizeLimit = 104857600;
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

    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }
    emit(UploadPreparationInProgress());
    final sizeLimit = (_targetDrive.isPrivate
        ? privateFileSizeLimit
        : 1.25 * math.pow(10, 9)) as int;
    final tooLargeFiles = [
      for (final file in files)
        if (await file.length() > sizeLimit) file.name
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
        _fileUploadHandles[uploadHandle.entity.id!] = uploadHandle;
      }
    } catch (err) {
      addError(err);
      return;
    }

    final uploadCost = _fileUploadHandles.values
        .map((f) => f.cost)
        .reduce((total, cost) => total + cost);

    var pstFee = await _pst
        .getPstFeePercentage()
        .then((feePercentage) =>
            // Workaround [BigInt] percentage division problems
            // by first multiplying by the percentage * 100 and then dividing by 100.
            uploadCost * BigInt.from(feePercentage * 100) ~/ BigInt.from(100))
        .catchError((_) => BigInt.zero,
            test: (err) => err is UnimplementedError);

    final minimumPstTip = BigInt.from(10000000);
    pstFee = pstFee > minimumPstTip ? pstFee : minimumPstTip;

    if (pstFee > BigInt.zero) {
      feeTx = await _arweave.client.transactions.prepare(
        Transaction(
          target: await _pst.getWeightedPstHolder(),
          quantity: pstFee,
        ),
        profile.wallet,
      )
        ..addApplicationTags()
        ..addTag('Type', 'fee')
        ..addTag(TipType.tagName, TipType.dataUpload);
      await feeTx!.sign(profile.wallet);
    }

    final totalCost = uploadCost + pstFee;

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
        files: _fileUploadHandles.values.toList(),
      ),
    );
  }

  Future<void> startUpload() async {
    //Check if the same wallet it being used before starting upload.
    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }
    emit(UploadInProgress(files: _fileUploadHandles.values.toList()));

    if (feeTx != null) {
      await _arweave.postTx(feeTx!);
    }

    await _driveDao.transaction(() async {
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
          emit(UploadInProgress(files: _fileUploadHandles.values.toList()));
        }
      }
    });

    unawaited(_profileCubit.refreshBalance());

    emit(UploadComplete());
  }

  Future<FileUploadHandle> prepareFileUpload(XFile file) async {
    final profile = _profileCubit.state as ProfileLoggedIn;

    final fileName = file.name;
    final filePath = '${_targetFolder.path}/$fileName';
    final fileEntity = FileEntity(
      driveId: _targetDrive.id,
      name: fileName,
      size: await file.length(),
      lastModifiedDate: await file.lastModified(),
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

    final fileData = await file.readAsBytes();

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

    uploadHandle.dataTx!.addApplicationTags();

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

      uploadHandle.bundleTx = await _arweave.prepareDataBundleTx(
        DataBundle(
          items: [
            entityDataItem,
            dataDataItem,
          ],
        ),
        profile.wallet,
      );
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
