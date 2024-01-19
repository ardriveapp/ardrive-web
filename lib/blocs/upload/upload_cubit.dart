import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';

import 'enums/conflicting_files_actions.dart';

part 'upload_state.dart';

final filesNamesToExclude = ['.DS_Store'];

enum UploadMethod { ar, turbo }

class UploadCubit extends Cubit<UploadState> {
  final String driveId;
  final String parentFolderId;
  final bool isDragNDrop;

  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final PstService _pst;
  final UploadFileSizeChecker _uploadFileSizeChecker;
  final ArDriveAuth _auth;
  final ArDriveUploadPreparationManager _arDriveUploadManager;
  final ActivityTracker _activityTracker;

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

      emit(uploadReady.copyWith(
        uploadMethod: method,
        isButtonToUploadEnabled: isButtonEnabled,
      ));
    }
  }

  List<UploadFile> files = [];
  IOFolder? folder;
  Map<String, WebFolder> foldersByPath = {};

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> conflictingFiles = {};
  final List<String> conflictingFolders = [];

  UploadCubit({
    required this.driveId,
    required this.parentFolderId,
    required this.files,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required PstService pst,
    required UploadFileSizeChecker uploadFileSizeChecker,
    required ArDriveAuth auth,
    required ArDriveUploadPreparationManager arDriveUploadManager,
    required ActivityTracker activityTracker,
    this.folder,
    this.uploadFolders = false,
    this.isDragNDrop = false,
  })  : _profileCubit = profileCubit,
        _uploadFileSizeChecker = uploadFileSizeChecker,
        _driveDao = driveDao,
        _pst = pst,
        _auth = auth,
        _arDriveUploadManager = arDriveUploadManager,
        _activityTracker = activityTracker,
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
      final largeFiles =
          await _uploadFileSizeChecker.getFilesAboveSizeLimit(files: files);

      if (largeFiles.isNotEmpty) {
        emit(
          UploadFileTooLarge(
            hasFilesToUpload: files.length > largeFiles.length,
            tooLargeFileNames: largeFiles,
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

    logger.d(
      'Upload preparation started. UploadMethod: $_uploadMethod',
    );

    try {
      final uploadPreparation = await _arDriveUploadManager.prepareUpload(
        params: UploadParams(
          user: _auth.currentUser,
          files: files,
          targetFolder: _targetFolder,
          targetDrive: _targetDrive,
          conflictingFiles: conflictingFiles,
          foldersByPath: foldersByPath,
        ),
      );

      final paymentInfo = uploadPreparation.uploadPaymentInfo;
      final uploadPlansPreparation = uploadPreparation.uploadPlansPreparation;

      _uploadMethod = paymentInfo.defaultPaymentMethod;
      logger.d('Upload method: $_uploadMethod');

      if (await _profileCubit.checkIfWalletMismatch()) {
        emit(UploadWalletMismatch());
        return;
      }

      bool isTurboZeroBalance =
          uploadPreparation.uploadPaymentInfo.turboBalance == BigInt.zero;

      logger.d(
        'Upload preparation finished\n'
        'UploadMethod: $_uploadMethod\n'
        'UploadPlan For AR: ${uploadPreparation.uploadPaymentInfo.arCostEstimate.toString()}\n'
        'UploadPlan For Turbo: ${uploadPreparation.uploadPlansPreparation.uploadPlanForTurbo.toString()}\n'
        'Turbo Balance: ${uploadPreparation.uploadPaymentInfo.turboBalance}\n'
        'AR Balance: ${_auth.currentUser.walletBalance}\n'
        'Is Turbo Upload Possible: ${paymentInfo.isUploadEligibleToTurbo}\n'
        'Is Zero Balance: $isTurboZeroBalance\n',
      );

      final literalBalance = convertWinstonToLiteralString(
          uploadPreparation.uploadPaymentInfo.turboBalance);
      final literalARBalance =
          convertWinstonToLiteralString(_auth.currentUser.walletBalance);

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
          arBalance: literalARBalance,
          uploadIsPublic: _targetDrive.isPublic,
          sufficientArBalance:
              profile.walletBalance >= paymentInfo.arCostEstimate.totalCost,
          uploadPlanForAR: uploadPlansPreparation.uploadPlanForAr,
          uploadPlanForTurbo: uploadPlansPreparation.uploadPlanForTurbo,
          isFreeThanksToTurbo: (paymentInfo.isFreeUploadPossibleUsingTurbo),
          sufficentCreditsBalance: sufficientBalanceToPayWithTurbo,
          uploadMethod: _uploadMethod!,
          isButtonToUploadEnabled: isButtonEnabled,
          isDragNDrop: isDragNDrop,
        ),
      );
    } catch (error, stacktrace) {
      logger.e('error mounting the upload', error, stacktrace);
      addError(error);
    }
  }

  bool hasEmittedError = false;
  bool hasEmittedWarning = false;
  bool uploadIsInProgress = false;

  Future<void> startUpload({
    required UploadPlan uploadPlanForAr,
    UploadPlan? uploadPlanForTurbo,
  }) async {
    if (uploadIsInProgress) {
      return;
    }

    uploadIsInProgress = true;

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

    final type =
        _uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo;
    final UploadContains contains = uploadFolders
        ? UploadContains.folder
        : files.length == 1
            ? UploadContains.singleFile
            : UploadContains.multipleFiles;
    PlausibleEventTracker.trackUploadConfirm(
      uploadType: type,
      uploadContains: contains,
    );

    logger.d(
        'Wallet verified. Starting bundle preparation.... Number of bundles: ${uploadPlanForAr.bundleUploadHandles.length}. Number of V2 files: ${uploadPlanForAr.fileV2UploadHandles.length}');

    if (_uploadMethod == UploadMethod.turbo) {
      await _verifyIfUploadContainsLargeFilesUsingTurbo();
      if ((_containsLargeTurboUpload ?? false) && !hasEmittedWarning) {
        emit(
          UploadShowingWarning(
            uploadPlanForAR: uploadPlanForAr,
            uploadPlanForTurbo: uploadPlanForTurbo,
          ),
        );
        hasEmittedWarning = true;
        return;
      }
    } else {
      _containsLargeTurboUpload = false;
    }

    if (uploadFolders) {
      await _uploadFolderUsingArDriveUploader();
      return;
    }

    await _uploadUsingArDriveUploader();

    return;
  }

  Future<void> _uploadFolderUsingArDriveUploader() async {
    final ardriveUploader = ArDriveUploader(
      turboUploadUri: Uri.parse(configService.config.defaultTurboUploadUrl!),
      metadataGenerator: ARFSUploadMetadataGenerator(
        tagsGenerator: ARFSTagsGenetator(
          appInfoServices: AppInfoServices(),
        ),
      ),
      arweave: Arweave(
        gatewayUrl: Uri.parse(configService.config.defaultArweaveGatewayUrl!),
      ),
      pstService: _pst,
    );

    final private = _targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(
            _targetDrive.id, _auth.currentUser.cipherKey)
        : null;

    List<(ARFSUploadMetadataArgs, IOEntity)> entities = [];

    for (var folder in foldersByPath.values) {
      final folderMetadata = ARFSUploadMetadataArgs(
        isPrivate: _targetDrive.isPrivate,
        driveId: _targetDrive.id,
        parentFolderId: folder.parentFolderId,
        privacy: _targetDrive.isPrivate ? 'private' : 'public',
        entityId: folder.id,
        type: _uploadMethod == UploadMethod.ar
            ? UploadType.d2n
            : UploadType.turbo,
      );

      entities.add((
        folderMetadata,
        UploadFolder(
          lastModifiedDate: DateTime.now(),
          name: folder.name,
          path: folder.path,
        ),
      ));
    }

    for (var file in files) {
      final id = conflictingFiles.containsKey(file.getIdentifier())
          ? conflictingFiles[file.getIdentifier()]
          : null;
      // TODO: We are verifying the conflicting files twice, we should do it only once.
      logger.d(
          'Reusing id? ${conflictingFiles.containsKey(file.getIdentifier())}');
      final fileMetadata = ARFSUploadMetadataArgs(
        isPrivate: _targetDrive.isPrivate,
        driveId: _targetDrive.id,
        parentFolderId: file.parentFolderId,
        privacy: _targetDrive.isPrivate ? 'private' : 'public',
        entityId: id,
        type: _uploadMethod == UploadMethod.ar
            ? UploadType.d2n
            : UploadType.turbo,
      );

      entities.add((fileMetadata, file.ioFile));
    }

    _activityTracker.setUploading(true);

    final uploadController = await ardriveUploader.uploadEntities(
      entities: entities,
      wallet: _auth.currentUser.wallet,
      type:
          _uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
      driveKey: driveKey,
    );

    uploadController.onError((tasks) {
      logger.e('Error uploading folders. Number of tasks: ${tasks.length}');
      addError(Exception('Error uploading'));
      hasEmittedError = true;
    });

    uploadController.onProgressChange(
      (progress) {
        emit(
          UploadInProgressUsingNewUploader(
            totalProgress: progress.progressInPercentage,
            equatableBust: UniqueKey(),
            progress: progress,
            controller: uploadController,
            uploadMethod: _uploadMethod!,
          ),
        );
      },
    );

    uploadController.onCompleteTask((task) {
      _saveEntityOnDB(task);
    });

    uploadController.onDone(
      (tasks) async {
        logger.d('Upload folders and files finished... Verifying results');

        if (tasks.any((element) => element.status == UploadStatus.failed)) {
          logger.e('One or more tasks failed. Emitting error');
          // if any of the files failed, we should throw an error
          addError(Exception('Error uploading'));
        }

        emit(UploadComplete());

        unawaited(_profileCubit.refreshBalance());
      },
    );
  }

  bool? _containsLargeTurboUpload;

  void retryUploads() {
    if (state is UploadFailure) {
      logger.i('Retrying uploads');

      final controller = (state as UploadFailure).controller!;

      controller.retryFailedTasks(_auth.currentUser.wallet);
    }
  }

  Future<void> _uploadUsingArDriveUploader() async {
    final ardriveUploader = ArDriveUploader(
      turboUploadUri: Uri.parse(configService.config.defaultTurboUploadUrl!),
      metadataGenerator: ARFSUploadMetadataGenerator(
        tagsGenerator: ARFSTagsGenetator(
          appInfoServices: AppInfoServices(),
        ),
      ),
      arweave: Arweave(
        gatewayUrl: Uri.parse(configService.config.defaultArweaveGatewayUrl!),
      ),
      pstService: _pst,
    );

    final private = _targetDrive.isPrivate;
    final driveKey = private
        ? await _driveDao.getDriveKey(
            _targetDrive.id, _auth.currentUser.cipherKey)
        : null;

    List<(ARFSUploadMetadataArgs, IOFile)> uploadFiles = [];

    for (var file in files) {
      final revisionAction = conflictingFiles.containsKey(file.getIdentifier())
          ? RevisionAction.uploadNewVersion
          : RevisionAction.create;

      final args = ARFSUploadMetadataArgs(
        isPrivate: _targetDrive.isPrivate,
        driveId: _targetDrive.id,
        parentFolderId: _targetFolder.id,
        privacy: _targetDrive.isPrivate ? 'private' : 'public',
        entityId: revisionAction == RevisionAction.uploadNewVersion
            ? conflictingFiles[file.getIdentifier()]
            : null,
        type: _uploadMethod == UploadMethod.ar
            ? UploadType.d2n
            : UploadType.turbo,
      );

      uploadFiles.add((args, file.ioFile));
    }

    _activityTracker.setUploading(true);

    /// Creates the uploader and starts the upload.
    final uploadController = await ardriveUploader.uploadFiles(
      files: uploadFiles,
      wallet: _auth.currentUser.wallet,
      driveKey: driveKey,
      type:
          _uploadMethod == UploadMethod.ar ? UploadType.d2n : UploadType.turbo,
    );

    uploadController.onError((tasks) {
      logger.e('Error uploading files. Number of tasks: ${tasks.length}');
      hasEmittedError = true;
      emit(
        UploadFailure(
          error: UploadErrors.unknown,
          failedTasks: tasks,
          controller: uploadController,
        ),
      );
    });

    uploadController.onProgressChange(
      (progress) async {
        // TODO: Save as the file is finished the upload

        emit(
          UploadInProgressUsingNewUploader(
            progress: progress,
            totalProgress: progress.progressInPercentage,
            controller: uploadController,
            equatableBust: UniqueKey(),
            uploadMethod: _uploadMethod!,
          ),
        );
      },
    );

    uploadController.onDone(
      (tasks) async {
        logger.d('Upload files finished... Verifying results');

        bool uploadSucced = true;

        if (tasks.any((element) => element.status == UploadStatus.failed)) {
          logger.e('One or more tasks failed. Emitting error');
          // if any of the files failed, we should throw an error
          addError(Exception('Error uploading'));

          PlausibleEventTracker.trackUploadFailure();
          uploadSucced = false;
        }

        unawaited(_profileCubit.refreshBalance());

        // all files are uploaded

        logger.i('Upload finished with success');

        emit(UploadComplete());

        if (uploadSucced) {
          PlausibleEventTracker.trackUploadSuccess();
        }
      },
    );

    uploadController.onCompleteTask((task) {
      unawaited(_saveEntityOnDB(task));
    });
  }

  Future<void> _verifyIfUploadContainsLargeFilesUsingTurbo() async {
    if (_containsLargeTurboUpload == null) {
      _containsLargeTurboUpload = false;

      if (await _uploadFileSizeChecker.hasFileAboveSizeLimit(files: files)) {
        _containsLargeTurboUpload = true;
        return;
      }
    }
  }

  Future _saveEntityOnDB(UploadTask task) async {
    // Single file only
    // TODO: abstract to the database interface.
    // TODO: improve API for finishing a file upload.
    final metadatas = task.content;

    if (metadatas != null) {
      for (var metadata in metadatas) {
        if (metadata is ARFSFileUploadMetadata) {
          final fileMetadata = metadata;

          final revisionAction = conflictingFiles.values.contains(metadata.id)
              ? RevisionAction.uploadNewVersion
              : RevisionAction.create;

          final entity = FileEntity(
            dataContentType: fileMetadata.dataContentType,
            dataTxId: fileMetadata.dataTxId,
            driveId: fileMetadata.driveId,
            id: fileMetadata.id,
            lastModifiedDate: fileMetadata.lastModifiedDate,
            name: fileMetadata.name,
            parentFolderId: fileMetadata.parentFolderId,
            size: fileMetadata.size,
            // TODO: pinnedDataOwnerAddress
          );

          if (fileMetadata.metadataTxId == null) {
            logger.e('Metadata tx id is null!');
            throw Exception('Metadata tx id is null');
          }

          entity.txId = fileMetadata.metadataTxId!;

          _driveDao.transaction(() async {
            // If path is a blob from drag and drop, use file name. Else use the path field from folder upload
            final filePath = '${_targetFolder.path}/${metadata.name}';
            await _driveDao.writeFileEntity(entity, filePath);
            await _driveDao.insertFileRevision(
              entity.toRevisionCompanion(
                performedAction: revisionAction,
              ),
            );
          });
        } else if (metadata is ARFSFolderUploadMetatadata) {
          final revisionAction = conflictingFolders.contains(metadata.name)
              ? RevisionAction.uploadNewVersion
              : RevisionAction.create;

          final entity = FolderEntity(
            driveId: metadata.driveId,
            id: metadata.id,
            name: metadata.name,
            parentFolderId: metadata.parentFolderId,
          );

          if (metadata.metadataTxId == null) {
            logger.e('Metadata tx id is null!');
            throw Exception('Metadata tx id is null');
          }

          entity.txId = metadata.metadataTxId!;

          final folderPath = foldersByPath.values
              .firstWhere((element) =>
                  element.name == metadata.name &&
                  element.parentFolderId == metadata.parentFolderId)
              .path;

          await _driveDao.transaction(() async {
            await _driveDao.createFolder(
              driveId: _targetDrive.id,
              parentFolderId: metadata.parentFolderId,
              folderName: metadata.name,
              path: folderPath,
              folderId: metadata.id,
            );
            await _driveDao.insertFolderRevision(
              entity.toRevisionCompanion(
                performedAction: revisionAction,
              ),
            );
          });
        }
      }
    }
  }

  Future<void> skipLargeFilesAndCheckForConflicts() async {
    emit(UploadPreparationInProgress());
    final List<String> filesToSkip =
        await _uploadFileSizeChecker.getFilesAboveSizeLimit(files: files);

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
      if (await _uploadFileSizeChecker.hasFileAboveWarningSizeLimit(
          files: files)) {
        emit(UploadShowingWarning(
          uploadPlanForAR: null,
          uploadPlanForTurbo: null,
        ));

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

  Future<void> cancelUpload() async {
    if (state is UploadInProgressUsingNewUploader) {
      try {
        final state = this.state as UploadInProgressUsingNewUploader;

        emit(
          UploadInProgressUsingNewUploader(
            controller: state.controller,
            equatableBust: state.equatableBust,
            progress: state.progress,
            totalProgress: state.totalProgress,
            isCanceling: true,
            uploadMethod: _uploadMethod!,
          ),
        );

        await state.controller.cancel();

        emit(
          UploadInProgressUsingNewUploader(
            controller: state.controller,
            equatableBust: state.equatableBust,
            progress: state.progress,
            totalProgress: state.totalProgress,
            isCanceling: false,
            uploadMethod: _uploadMethod!,
          ),
        );

        emit(UploadCanceled());
      } catch (e) {
        logger.e('Error canceling upload', e);
      }
    }
  }
}

class UploadFolder extends IOFolder {
  UploadFolder({
    required this.name,
    required this.path,
    required this.lastModifiedDate,
  });

  @override
  final DateTime lastModifiedDate;

  @override
  Future<List<IOEntity>> listContent() {
    throw UnimplementedError();
  }

  @override
  Future<List<IOFile>> listFiles() {
    throw UnimplementedError();
  }

  @override
  Future<List<IOFolder>> listSubfolders() {
    throw UnimplementedError();
  }

  @override
  final String name;

  @override
  // TODO: implement path
  final String path;

  @override
  List<Object?> get props => [name, path, lastModifiedDate];
}
