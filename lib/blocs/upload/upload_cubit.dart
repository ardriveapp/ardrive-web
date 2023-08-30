import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/limits.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'enums/conflicting_files_actions.dart';

part 'upload_state.dart';

final filesNamesToExclude = ['.DS_Store'];

enum UploadMethod { ar, turbo }

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String parentFolderId;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ArweaveService _arweave;
  final TurboUploadService _turbo;
  final PstService _pst;
  final UploadFileChecker _uploadFileChecker;
  final ArDriveAuth _auth;
  final ArDriveUploadPreparationManager _arDriveUploadManager;

  late bool uploadFolders;
  late Drive _targetDrive;
  late FolderEntry _targetFolder;
  UploadMethod? _uploadMethod;

  void setUploadMethod(UploadMethod? method) {
    logger.d('Upload method set to $method');
    _uploadMethod = method;

    bool isButtonEnabled = false;

    if (state is UploadReady) {
      final uploadReady = state as UploadReady;
      logger.d(
          'Sufficient Balance To Pay With AR: ${uploadReady.sufficientArBalance}');

      if (_uploadMethod == UploadMethod.ar && uploadReady.sufficientArBalance) {
        logger.d('Enabling button for AR payment method');
        isButtonEnabled = true;
      } else if (_uploadMethod == UploadMethod.turbo &&
          uploadReady.isTurboUploadPossible &&
          uploadReady.sufficentCreditsBalance) {
        logger.d('Enabling button for Turbo payment method');
        isButtonEnabled = true;
      } else if (uploadReady.isFreeThanksToTurbo) {
        logger.d('Enabling button for free upload using Turbo');
        isButtonEnabled = true;
      } else {
        logger.d('Disabling button');
      }

      emit((state as UploadReady).copyWith(
          uploadMethod: method, isButtonToUploadEnabled: isButtonEnabled));
    }
  }

  List<UploadFile> files = [];
  Map<String, WebFolder> foldersByPath = {};

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};
  final List<String> conflictingFolders = [];

  bool fileSizeWithinBundleLimits(int size) => size < bundleSizeLimit;

  UploadCubit({
    required this.driveId,
    required this.parentFolderId,
    required this.files,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ArweaveService arweave,
    required TurboUploadService turbo,
    required PstService pst,
    required UploadFileChecker uploadFileChecker,
    required ArDriveAuth auth,
    required ArDriveUploadPreparationManager arDriveUploadManager,
    this.uploadFolders = false,
  })  : _profileCubit = profileCubit,
        _uploadFileChecker = uploadFileChecker,
        _driveDao = driveDao,
        _arweave = arweave,
        _turbo = turbo,
        _pst = pst,
        _auth = auth,
        _arDriveUploadManager = arDriveUploadManager,
        super(UploadPreparationInProgress());

  Future<void> startUploadPreparation({
    bool isRetryingToPayWithTurbo = false,
  }) async {
    files.removeWhere((file) => filesNamesToExclude.contains(file.ioFile.name));
    _targetDrive = await _driveDao.driveById(driveId: driveId).getSingle();
    _targetFolder = await _driveDao
        .folderById(driveId: driveId, folderId: parentFolderId)
        .getSingle();

    // TODO: check if the backend refreshed the balance instead of a timer
    if (isRetryingToPayWithTurbo) {
      emit(UploadPreparationInProgress());

      /// necessary to wait for backend update the balance
      await Future.delayed(const Duration(seconds: 2));
    }

    emit(UploadPreparationInitialized());
  }

  Future<void> checkConflicts() async {
    if (uploadFolders) {
      return await checkConflictingFolders();
    }

    await checkConflictingFiles();
  }

  /// Tries to find a files that conflict with the files in the target folder.
  ///
  /// If there's one, prompt the user to upload the file as a version of the existing one.
  /// If there isn't one, prepare to upload the file.
  Future<void> checkConflictingFolders() async {
    emit(UploadPreparationInProgress());
    if (uploadFolders) {
      final folderPrepareResult =
          await generateFoldersAndAssignParentsForFiles(files);
      files = folderPrepareResult.files;
      foldersByPath = folderPrepareResult.foldersByPath;
    }
    for (final file in files) {
      final fileName = file.ioFile.name;

      final existingFolderName = await _driveDao
          .foldersInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: file.parentFolderId,
            name: fileName,
          )
          .map((f) => f.name)
          .getSingleOrNull();

      if (existingFolderName != null) {
        conflictingFolders.add(existingFolderName);
      }
    }

    if (conflictingFolders.isNotEmpty) {
      emit(
        UploadFolderNameConflict(
          areAllFilesConflicting: conflictingFolders.length == files.length,
          conflictingFileNames: conflictingFolders,
        ),
      );
    } else {
      await checkConflictingFiles();
    }
  }

  Future<void> checkFilesAboveLimit() async {
    if (_isAPrivateUpload()) {
      final tooLargeFiles = await _uploadFileChecker
          .checkAndReturnFilesAbovePrivateLimit(files: files);

      if (tooLargeFiles.isNotEmpty) {
        emit(
          UploadFileTooLarge(
            hasFilesToUpload: files.length > tooLargeFiles.length,
            tooLargeFileNames: tooLargeFiles,
            isPrivate: _isAPrivateUpload(),
          ),
        );
        return;
      }
    }

    // If we don't have any file above limit, we can check conflicts
    checkConflicts();
  }

  Future<void> checkConflictingFiles() async {
    emit(UploadPreparationInProgress());

    _removeFilesWithFolderNameConflicts();

    for (final file in files) {
      final fileName = file.ioFile.name;
      final existingFileId = await _driveDao
          .filesInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: file.parentFolderId,
            name: fileName,
          )
          .map((f) => f.id)
          .getSingleOrNull();

      if (existingFileId != null) {
        logger.d('Found conflicting file. Existing file id: $existingFileId');
        conflictingFiles[file.getIdentifier()] = existingFileId;
      }
    }
    if (conflictingFiles.isNotEmpty) {
      emit(
        UploadFileConflict(
          areAllFilesConflicting: conflictingFiles.length == files.length,
          conflictingFileNames: conflictingFiles.keys.toList(),
        ),
      );
    } else {
      await prepareUploadPlanAndCostEstimates();
    }
  }

  /// Generate Folders and assign parentFolderIds
  Future<FolderPrepareResult> generateFoldersAndAssignParentsForFiles(
    List<UploadFile> files,
  ) async {
    final folders = UploadPlanUtils.generateFoldersForFiles(
      files,
    );
    final foldersToSkip = [];
    for (var folder in folders.values) {
      //If The folders map contains the immediate ancestor of the current folder
      //we use the id of that folder, otherwise use targetFolder as root

      folder.parentFolderId = folders.containsKey(folder.parentFolderPath)
          ? folders[folder.parentFolderPath]!.id
          : _targetFolder.id;

      final existingFolderId = await _driveDao
          .foldersInFolderWithName(
            driveId: driveId,
            name: folder.name,
            parentFolderId: folder.parentFolderId,
          )
          .map((f) => f.id)
          .getSingleOrNull();
      final existingFileId = await _driveDao
          .filesInFolderWithName(
            driveId: driveId,
            name: folder.name,
            parentFolderId: folders[folder.parentFolderPath] != null
                ? folders[folder.parentFolderPath]!.id
                : _targetFolder.id,
          )
          .map((f) => f.id)
          .getSingleOrNull();
      if (existingFolderId != null) {
        folder.id = existingFolderId;
        foldersToSkip.add(folder);
      }
      if (existingFileId != null) {
        conflictingFolders.add(folder.name);
      }
      folder.path = folder.parentFolderPath.isNotEmpty
          ? '${_targetFolder.path}/${folder.parentFolderPath}/${folder.name}'
          : '${_targetFolder.path}/${folder.name}';
    }
    final filesToUpload = <UploadFile>[];
    for (var file in files) {
      final fileFolder = getDirname(file.relativeTo != null
          ? file.ioFile.path.replaceFirst('${file.relativeTo}/', '')
          : file.ioFile.path);
      final parentFolderId = folders[fileFolder]?.id ?? _targetFolder.id;
      filesToUpload.add(
        UploadFile(
          ioFile: file.ioFile,
          parentFolderId: parentFolderId,
          relativeTo: file.relativeTo,
        ),
      );
    }
    folders.removeWhere((key, value) => foldersToSkip.contains(value));
    return FolderPrepareResult(files: filesToUpload, foldersByPath: folders);
  }

  Future<void> prepareUploadPlanAndCostEstimates({
    UploadActions? uploadAction,
  }) async {
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

    if (uploadAction == UploadActions.skip) {
      _removeFilesWithFileNameConflicts();
    }

    logger.i(
      'Upload preparation started. UploadMethod: $_uploadMethod',
    );

    try {
      final uploadPreparation = await _arDriveUploadManager.prepareUpload(
        params: UploadParams(
          user: _auth.currentUser!,
          files: files,
          targetFolder: _targetFolder,
          targetDrive: _targetDrive,
          conflictingFiles: conflictingFiles,
          foldersByPath: foldersByPath,
        ),
      );

      _uploadMethod = uploadPreparation.uploadPaymentInfo.defaultPaymentMethod;

      logger.d('Upload method: $_uploadMethod');

      final paymentInfo = uploadPreparation.uploadPaymentInfo;
      final uploadPlansPreparation = uploadPreparation.uploadPlansPreparation;

      if (await _profileCubit.checkIfWalletMismatch()) {
        emit(UploadWalletMismatch());
        return;
      }

      bool isTurboZeroBalance =
          uploadPreparation.uploadPaymentInfo.turboBalance == BigInt.zero;

      logger.i(
        'Upload preparation finished\n'
        'UploadMethod: $_uploadMethod\n'
        'UploadPlan For AR: ${uploadPreparation.uploadPaymentInfo.arCostEstimate.toString()}\n'
        'UploadPlan For Turbo: ${uploadPreparation.uploadPlansPreparation.uploadPlanForTurbo.toString()}\n'
        'Turbo Balance: ${uploadPreparation.uploadPaymentInfo.turboBalance}\n'
        'AR Balance: ${_auth.currentUser!.walletBalance}\n'
        'Is Turbo Upload Possible: ${paymentInfo.isUploadEligibleToTurbo}\n'
        'Is Zero Balance: $isTurboZeroBalance\n',
      );

      final literalBalance = convertCreditsToLiteralString(
          uploadPreparation.uploadPaymentInfo.turboBalance);

      bool isButtonEnabled = false;
      bool sufficientBalanceToPayWithAR =
          profile.walletBalance >= paymentInfo.arCostEstimate.totalCost;
      bool sufficientBalanceToPayWithTurbo =
          paymentInfo.turboCostEstimate.totalCost <=
              uploadPreparation.uploadPaymentInfo.turboBalance;

      logger.d(
          'Sufficient Balance To Pay With AR: $sufficientBalanceToPayWithAR');

      if (_uploadMethod == UploadMethod.ar && sufficientBalanceToPayWithAR) {
        logger.d('Enabling button for AR payment method');
        isButtonEnabled = true;
      } else if (_uploadMethod == UploadMethod.turbo &&
          paymentInfo.isUploadEligibleToTurbo &&
          paymentInfo.isTurboAvailable &&
          sufficientBalanceToPayWithTurbo) {
        logger.d('Enabling button for Turbo payment method');
        isButtonEnabled = true;
      } else if (paymentInfo.isFreeUploadPossibleUsingTurbo) {
        logger.d('Enabling button for free upload using Turbo');
        isButtonEnabled = true;
      } else {
        logger.d('Disabling button');
      }

      emit(
        UploadReady(
          isTurboUploadPossible: paymentInfo.isUploadEligibleToTurbo &&
              paymentInfo.isTurboAvailable,
          isZeroBalance: isTurboZeroBalance,
          turboCredits: literalBalance,
          uploadSize: paymentInfo.totalSize,
          costEstimateAr: paymentInfo.arCostEstimate,
          costEstimateTurbo: paymentInfo.turboCostEstimate,
          credits: literalBalance,
          arBalance:
              convertCreditsToLiteralString(_auth.currentUser!.walletBalance),
          uploadIsPublic: _targetDrive.isPublic,
          sufficientArBalance:
              profile.walletBalance >= paymentInfo.arCostEstimate.totalCost,
          uploadPlanForAR: uploadPlansPreparation.uploadPlanForAr,
          uploadPlanForTurbo: uploadPlansPreparation.uploadPlanForTurbo,
          isFreeThanksToTurbo: (paymentInfo.isFreeUploadPossibleUsingTurbo),
          sufficentCreditsBalance: sufficientBalanceToPayWithTurbo,
          uploadMethod: _uploadMethod!,
          isButtonToUploadEnabled: isButtonEnabled,
        ),
      );
    } catch (error, stacktrace) {
      logger.e('error mounting the upload', error, stacktrace);
      addError(error);
    }
  }

  bool hasEmittedError = false;

  Future<void> startUpload({
    required UploadPlan uploadPlanForAr,
    UploadPlan? uploadPlanForTurbo,
  }) async {
    UploadPlan uploadPlan;

    if (_uploadMethod == UploadMethod.ar || uploadPlanForTurbo == null) {
      uploadPlan = uploadPlanForAr;
    } else {
      uploadPlan = uploadPlanForTurbo;
    }

    logger.d('Max files per bundle: ${uploadPlan.maxDataItemCount}');

    logger.i('Starting upload...');

    //Check if the same wallet it being used before starting upload.
    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadWalletMismatch());
      return;
    }

    emit(
      UploadSigningInProgress(
        uploadPlan: uploadPlan,
        isArConnect: await _profileCubit.isCurrentProfileArConnect(),
      ),
    );

    logger.i(
        'Wallet verified. Starting bundle preparation.... Number of bundles: ${uploadPlanForAr.bundleUploadHandles.length}. Number of V2 files: ${uploadPlanForAr.fileV2UploadHandles.length}');

    final uploader = _getUploader();

    await for (final progress in uploader.uploadFromHandles(
      bundleHandles: uploadPlan.bundleUploadHandles,
      fileV2Handles: uploadPlan.fileV2UploadHandles.values.toList(),
    )) {
      emit(
        UploadInProgress(
          uploadPlan: uploadPlan,
          progress: progress,
        ),
      );
    }

    logger.i('Upload finished');

    unawaited(_profileCubit.refreshBalance());

    emit(UploadComplete());
  }

  Future<void> skipLargeFilesAndCheckForConflicts() async {
    emit(UploadPreparationInProgress());
    final List<String> filesToSkip = await _uploadFileChecker
        .checkAndReturnFilesAbovePrivateLimit(files: files);

    files.removeWhere(
      (file) => filesToSkip.contains(file.getIdentifier()),
    );

    await checkConflicts();
  }

  void _removeFilesWithFileNameConflicts() {
    files.removeWhere(
      (file) => conflictingFiles.containsKey(file.getIdentifier()),
    );
  }

  void _removeFilesWithFolderNameConflicts() {
    files.removeWhere((file) => conflictingFolders.contains(file.ioFile.name));
  }

  Future<void> verifyFilesAboveWarningLimit() async {
    if (!_targetDrive.isPrivate) {
      bool fileAboveWarningLimit =
          await _uploadFileChecker.hasFileAboveSafePublicSizeLimit(
        files: files,
      );

      if (fileAboveWarningLimit) {
        emit(UploadShowingWarning(reason: UploadWarningReason.fileTooLarge));

        return;
      }
      await prepareUploadPlanAndCostEstimates();
    }

    checkFilesAboveLimit();
  }

  @visibleForTesting
  bool isPrivateForTesting = false;

  bool _isAPrivateUpload() {
    return isPrivateForTesting || _targetDrive.isPrivate;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    if (error is TurboUploadTimeoutException) {
      emit(UploadFailure(error: UploadErrors.turboTimeout));

      return;
    }

    emit(UploadFailure(error: UploadErrors.unknown));
    logger.e('Failed to upload file', error, stackTrace);
    super.onError(error, stackTrace);
  }

  ArDriveUploader _getUploader() {
    final wallet = _auth.currentUser!.wallet;

    final turboUploader = TurboUploader(_turbo, wallet);
    final arweaveUploader = ArweaveBundleUploader(_arweave.client);

    logger.i(
        'Uploaders created: Turbo: $turboUploader, Arweave: $arweaveUploader');

    final bundleUploader = BundleUploader(
      turboUploader,
      arweaveUploader,
      _uploadMethod == UploadMethod.turbo,
    );

    final v2Uploader = FileV2Uploader(_arweave.client, _arweave);

    final uploader = ArDriveUploader(
      bundleUploader: bundleUploader,
      fileV2Uploader: v2Uploader,
      prepareBundle: (handle) async {
        logger.i(
            'Preparing bundle.. using turbo: ${_uploadMethod == UploadMethod.turbo}');

        await handle.prepareAndSignBundleTransaction(
          tabVisibilitySingleton: TabVisibilitySingleton(),
          arweaveService: _arweave,
          turboUploadService: _turbo,
          pstService: _pst,
          wallet: _auth.currentUser!.wallet,
          isArConnect: await _profileCubit.isCurrentProfileArConnect(),
          useTurbo: _uploadMethod == UploadMethod.turbo,
        );

        logger.i('Bundle preparation finished');
      },
      prepareFile: (handle) async {
        logger.i('Preparing file...');

        await handle.prepareAndSignTransactions(
          arweaveService: _arweave,
          wallet: wallet,
          pstService: _pst,
        );
      },
      onFinishFileUpload: (handle) async {
        unawaited(handle.writeFileEntityToDatabase(driveDao: _driveDao));
      },
      onFinishBundleUpload: (handle) async {
        unawaited(handle.writeBundleItemsToDatabase(driveDao: _driveDao));
      },
      onUploadBundleError: (handle, error) async {
        if (!hasEmittedError) {
          addError(error);
          hasEmittedError = true;
        }
      },
      onUploadFileError: (handle, error) async {
        if (!hasEmittedError) {
          addError(error);
          hasEmittedError = true;
        }
      },
    );

    return uploader;
  }
}
