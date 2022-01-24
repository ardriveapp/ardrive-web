import 'dart:async';
import 'dart:math' as math;

import 'package:ardrive/blocs/upload/bundle_upload_handle.dart';
import 'package:ardrive/blocs/upload/data_item_upload_handle.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/bundles/next_fit_bundle_packer.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
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
  final Map<String, FileUploadHandle> _v2FileUploadHandles = {};
  final Map<String, DataItemUploadHandle> _dataItemUploadHandles = {};

  /// A list of all multi file upload handles containing bundles of multiple files
  final List<BundleUploadHandle> _bundleUploadHandles = [];

  /// The [Transaction] that pays `pstFee` to a random PST holder. (Only for v2 transaction uploads)
  Transaction? v2FilesFeeTx;

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
        if (await file.length() > sizeLimit) file.name
    ];

    if (tooLargeFiles.isNotEmpty) {
      emit(UploadFileTooLarge(
        tooLargeFileNames: tooLargeFiles,
        isPrivate: _targetDrive.isPrivate,
      ));
      return;
    }
    await prepareFiles(files);
    await prepareBundleHandles();

    final dataItemsCost = _bundleUploadHandles.isNotEmpty
        ? await estimateBundleCosts(_bundleUploadHandles)
        : BigInt.zero;
    var v2FilesUploadCost = BigInt.zero;
    for (final value in _v2FileUploadHandles.values
        .map((e) async => await e.estimateV2UploadCost())) {
      v2FilesUploadCost += await value;
    }

    final bundlePstFee = await _pst.getPSTFee(dataItemsCost);

    if (_v2FileUploadHandles.isNotEmpty) {
      v2FilesFeeTx = await prepareAndSignV2FilesTipTx(
          wallet: profile.wallet, v2FilesUploadCost: v2FilesUploadCost);
    }
    final v2FilesPstFee = (v2FilesFeeTx?.quantity ?? BigInt.zero);
    final totalCost = v2FilesUploadCost + dataItemsCost + bundlePstFee;

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
        pstFee: v2FilesPstFee,
        totalCost: totalCost,
        uploadIsPublic: _targetDrive.isPublic,
        sufficientArBalance: profile.walletBalance >= totalCost,
        files: _v2FileUploadHandles.values.toList(),
        bundles: _bundleUploadHandles,
      ),
    );
  }

  Future<Transaction?> prepareAndSignV2FilesTipTx({
    required Wallet wallet,
    required v2FilesUploadCost,
  }) async {
    if (v2FilesUploadCost <= BigInt.zero) {
      return null;
    }
    final packageInfo = await PackageInfo.fromPlatform();
    final pstFee = await _pst.getPSTFee(v2FilesUploadCost);
    final quantity =
        pstFee > minimumPstTip ? v2FilesFeeTx!.reward : minimumPstTip;

    final feeTx = await _arweave.client.transactions.prepare(
      Transaction(
        target: await _pst.getWeightedPstHolder(),
        quantity: quantity,
      ),
      wallet,
    )
      ..addApplicationTags(version: packageInfo.version)
      ..addTag('Type', 'fee')
      ..addTag(TipType.tagName, TipType.dataUpload);
    await feeTx.sign(wallet);
    return feeTx;
  }

  Future<BigInt> estimateBundleCosts(
    List<BundleUploadHandle> bundleUploadHandles,
  ) async {
    var totalCost = BigInt.zero;
    for (var bundle in bundleUploadHandles) {
      totalCost += await bundle.estimateBundleCost(arweave: _arweave);
    }
    return totalCost;
  }

  Future<void> prepareBundleHandles() async {
    // NOTE: Using maxFilesPerBundle since FileUploadHandles have 2 data items
    final bundleItems = await NextFitBundlePacker<DataItemUploadHandle>(
      maxBundleSize: bundleSizeLimit,
      maxDataItemCount: maxFilesPerBundle,
    ).packItems(_dataItemUploadHandles.values.toList());
    for (var uploadHandles in bundleItems) {
      emit(
        UploadBundlingInProgress(
          isArConnect: await _profileCubit.isCurrentProfileArConnect(),
        ),
      );
      var uploadSize = 0;
      for (var uploadHandle in uploadHandles) {
        uploadSize += uploadHandle.entity.size!;
      }

      final bundleToUpload = BundleUploadHandle(
        List.from(uploadHandles),
        uploadSize,
      );
      _bundleUploadHandles.add(bundleToUpload);
      uploadHandles.clear();
    }
    _dataItemUploadHandles.clear();
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

    if (v2FilesFeeTx != null && _v2FileUploadHandles.isNotEmpty) {
      await _arweave.postTx(v2FilesFeeTx!);
    }

    // Used since each prepareBundle executes database operations
    await _driveDao.transaction(() async {
      // Upload Bundles
      for (var bundleHandle in _bundleUploadHandles) {
        emit(
          UploadBundlingInProgress(
            isArConnect: await _profileCubit.isCurrentProfileArConnect(),
          ),
        );

        await bundleHandle.prepareBundle(
          arweaveService: _arweave,
          pstService: _pst,
          wallet: profile.wallet,
        );
        await for (final _ in bundleHandle.upload(_arweave)) {
          emit(UploadInProgress(
            files: _v2FileUploadHandles.values.toList(),
            bundles: _bundleUploadHandles,
          ));
        }
        bundleHandle.dispose();
      }

      // Upload V2 Files
      for (final uploadHandle in _v2FileUploadHandles.values) {
        await uploadHandle.prepareAndSign();
        await uploadHandle.writeEntityToDatabase();
        await for (final _ in uploadHandle.upload(_arweave)) {
          emit(UploadInProgress(
            files: _v2FileUploadHandles.values.toList(),
            bundles: _bundleUploadHandles,
          ));
        }
      }
    });

    unawaited(_profileCubit.refreshBalance());

    emit(UploadComplete());
  }

  Future<void> prepareFiles(List<XFile> files) async {
    final profile = _profileCubit.state as ProfileLoggedIn;
    for (var file in files) {
      final fileName = file.name;
      final filePath = '${_targetFolder.path}/$fileName';
      final fileSize = await file.length();
      final fileEntity = FileEntity(
        driveId: _targetDrive.id,
        name: fileName,
        size: fileSize,
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

      final revisionAction = !conflictingFiles.containsKey(file.name)
          ? RevisionAction.create
          : RevisionAction.uploadNewVersion;

      if (fileSize < bundleSizeLimit) {
        _dataItemUploadHandles[fileEntity.id!] = DataItemUploadHandle(
          entity: fileEntity,
          path: filePath,
          file: file,
          isPrivate: private,
          driveKey: driveKey,
          fileKey: fileKey,
          arweave: _arweave,
          driveDao: _driveDao,
          wallet: profile.wallet,
          revisionAction: revisionAction,
        );
      } else {
        _v2FileUploadHandles[fileEntity.id!] = FileUploadHandle(
          entity: fileEntity,
          path: filePath,
          file: file,
          isPrivate: private,
          driveKey: driveKey,
          fileKey: fileKey,
          arweave: _arweave,
          driveDao: _driveDao,
          wallet: profile.wallet,
          revisionAction: revisionAction,
        );
      }
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(UploadFailure());
    super.onError(error, stackTrace);

    print('Failed to upload file: $error $stackTrace');
  }
}
