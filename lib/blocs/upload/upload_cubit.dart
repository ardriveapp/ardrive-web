import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
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
import 'package:reactive_forms/reactive_forms.dart';

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
  final ActivityTracker _activityTracker;
  final LicenseService _licenseService;

  late bool uploadFolders;
  late Drive _targetDrive;
  late FolderEntry _targetFolder;
  UploadMethod? _uploadMethod;

  void setUploadMethod(
    UploadMethod? method,
    UploadPaymentMethodInfo paymentInfo,
    bool canUpload,
  ) {
    logger.d('Upload method set to $method');
    _uploadMethod = method;

    if (state is UploadReady) {
      final uploadReady = state as UploadReady;

      emit(uploadReady.copyWith(
        paymentInfo: paymentInfo,
        uploadMethod: method,
        isNextButtonEnabled: canUpload,
      ));
    } else if (state is UploadReadyToPrepare) {
      emit(UploadReady(
        params: (state as UploadReadyToPrepare).params,
        paymentInfo: paymentInfo,
        numberOfFiles: files.length,
        uploadIsPublic: !_targetDrive.isPrivate,
        isDragNDrop: isDragNDrop,
        isNextButtonEnabled: canUpload,
        isArConnect: (state as UploadReadyToPrepare).isArConnect,
      ));
    }
  }

  void initialScreenUpload() {
    if (state is UploadReady) {
      final readyState = state as UploadReady;
      startUpload(
        uploadPlanForAr: readyState.paymentInfo.uploadPlanForAR!,
        uploadPlanForTurbo: readyState.paymentInfo.uploadPlanForTurbo,
      );
    }
  }

  void initialScreenNext({required LicenseCategory licenseCategory}) {
    if (state is UploadReady) {
      final readyState = state as UploadReady;
      emit(UploadConfiguringLicense(
        readyState: readyState,
        licenseCategory: licenseCategory,
      ));
    }
  }

  void configuringLicenseBack() {
    if (state is UploadConfiguringLicense) {
      final configuringLicense = state as UploadConfiguringLicense;
      final prevState = configuringLicense.readyState;
      emit(prevState);
    }
  }

  void configuringLicenseNext() {
    if (state is UploadConfiguringLicense) {
      final configuringLicense = state as UploadConfiguringLicense;

      late LicenseState licenseState;
      switch (configuringLicense.licenseCategory) {
        case LicenseCategory.udl:
          licenseState = LicenseState(
            meta: udlLicenseDefault,
            params: udlFormToLicenseParams(_licenseUdlParamsForm),
          );
        case LicenseCategory.cc:
          final LicenseMeta licenseMeta =
              _licenseCcTypeForm.control('ccTypeField').value;
          licenseState = LicenseState(meta: licenseMeta);
        default:
          throw StateError(
              'Invalid license category: ${configuringLicense.licenseCategory}');
      }

      emit(UploadReviewWithLicense(
        readyState: configuringLicense.readyState,
        licenseCategory: configuringLicense.licenseCategory,
        licenseState: licenseState,
      ));
    }
  }

  void reviewBack() {
    if (state is UploadReviewWithLicense) {
      final reviewWithLicense = state as UploadReviewWithLicense;
      final UploadReady readyState = reviewWithLicense.readyState;
      final licenseCategory = reviewWithLicense.licenseCategory;
      final prevState = UploadConfiguringLicense(
        readyState: readyState,
        licenseCategory: licenseCategory,
      );
      emit(prevState);
    }
  }

  void reviewUpload() {
    if (state is UploadReviewWithLicense) {
      final reviewWithLicense = state as UploadReviewWithLicense;
      startUpload(
        uploadPlanForAr:
            reviewWithLicense.readyState.paymentInfo.uploadPlanForAR!,
        uploadPlanForTurbo:
            reviewWithLicense.readyState.paymentInfo.uploadPlanForTurbo,
        licenseStateConfigured: reviewWithLicense.licenseState,
      );
    }
  }

  final _licenseCategoryForm = FormGroup({
    'licenseCategory': FormControl<LicenseCategory?>(
      validators: [],
      value: null,
    ),
  });
  final _licenseUdlParamsForm = createUdlParamsForm();
  final _licenseCcTypeForm = createCcTypeForm();

  FormGroup get licenseCategoryForm => _licenseCategoryForm;
  FormGroup get licenseUdlParamsForm => _licenseUdlParamsForm;
  FormGroup get licenseCcTypeForm => _licenseCcTypeForm;

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
    required LicenseService licenseService,
    this.folder,
    this.uploadFolders = false,
    this.isDragNDrop = false,
  })  : _profileCubit = profileCubit,
        _uploadFileSizeChecker = uploadFileSizeChecker,
        _driveDao = driveDao,
        _pst = pst,
        _auth = auth,
        _activityTracker = activityTracker,
        _licenseService = licenseService,
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
            parentFolderId: folder.parentFolderId,
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
      if (await _profileCubit.checkIfWalletMismatch()) {
        emit(UploadWalletMismatch());
        return;
      }

      emit(
        UploadReadyToPrepare(
          params: UploadParams(
            user: _auth.currentUser,
            files: files,
            targetFolder: _targetFolder,
            targetDrive: _targetDrive,
            conflictingFiles: conflictingFiles,
            foldersByPath: foldersByPath,
          ),
          isArConnect: await _profileCubit.isCurrentProfileArConnect(),
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
    LicenseState? licenseStateConfigured,
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
      await _uploadFolderUsingArDriveUploader(
        licenseStateConfigured: licenseStateConfigured,
      );
      return;
    }

    await _uploadUsingArDriveUploader(
      licenseStateConfigured: licenseStateConfigured,
    );

    return;
  }

  Future<void> _uploadFolderUsingArDriveUploader({
    LicenseState? licenseStateConfigured,
  }) async {
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
      final fileId = conflictingFiles.containsKey(file.getIdentifier())
          ? conflictingFiles[file.getIdentifier()]
          : null;
      // TODO: We are verifying the conflicting files twice, we should do it only once.
      logger.d(
          'Reusing id? ${conflictingFiles.containsKey(file.getIdentifier())}');

      final licenseStateResolved =
          licenseStateConfigured ?? await _licenseStateForFileId(fileId);

      final fileMetadata = ARFSUploadMetadataArgs(
        isPrivate: _targetDrive.isPrivate,
        driveId: _targetDrive.id,
        parentFolderId: file.parentFolderId,
        privacy: _targetDrive.isPrivate ? 'private' : 'public',
        entityId: fileId,
        type: _uploadMethod == UploadMethod.ar
            ? UploadType.d2n
            : UploadType.turbo,
        licenseDefinitionTxId: licenseStateResolved?.meta.licenseDefinitionTxId,
        licenseAdditionalTags: licenseStateResolved?.params?.toAdditionalTags(),
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

  Future<void> _uploadUsingArDriveUploader({
    LicenseState? licenseStateConfigured,
  }) async {
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
      final conflictingId = conflictingFiles[file.getIdentifier()];
      final revisionAction = conflictingId != null
          ? RevisionAction.uploadNewVersion
          : RevisionAction.create;

      final licenseStateResolved =
          licenseStateConfigured ?? await _licenseStateForFileId(conflictingId);

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
        licenseDefinitionTxId: licenseStateResolved?.meta.licenseDefinitionTxId,
        licenseAdditionalTags: licenseStateResolved?.params?.toAdditionalTags(),
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
            licenseTxId: fileMetadata.licenseTxId,
            driveId: fileMetadata.driveId,
            id: fileMetadata.id,
            lastModifiedDate: fileMetadata.lastModifiedDate,
            name: fileMetadata.name,
            parentFolderId: fileMetadata.parentFolderId,
            size: fileMetadata.size,
            // TODO: pinnedDataOwnerAddress
          );

          LicensesCompanion? licensesCompanion;
          if (fileMetadata.licenseTxId != null) {
            final licenseType = _licenseService
                .licenseTypeByTxId(fileMetadata.licenseDefinitionTxId!)!;

            final licenseState = LicenseState(
              meta: _licenseService.licenseMetaByType(licenseType),
              params: _licenseService.paramsFromAdditionalTags(
                licenseType: licenseType,
                additionalTags: fileMetadata.licenseAdditionalTags,
              ),
            );
            licensesCompanion = _licenseService.toCompanion(
              licenseState: licenseState,
              dataTxId: fileMetadata.dataTxId!,
              fileId: fileMetadata.id,
              driveId: driveId,
              licenseTxId: fileMetadata.licenseTxId!,
              licenseTxType: fileMetadata.licenseTxId == fileMetadata.dataTxId
                  ? LicenseTxType.composed
                  : LicenseTxType.assertion,
            );
          }

          if (fileMetadata.metadataTxId == null) {
            logger.e('Metadata tx id is null!');
            throw Exception('Metadata tx id is null');
          }

          entity.txId = fileMetadata.metadataTxId!;

          _driveDao.transaction(() async {
            final filePath = '${_targetFolder.path}/${metadata.name}';
            await _driveDao.writeFileEntity(entity, filePath);
            await _driveDao.insertFileRevision(
              entity.toRevisionCompanion(
                performedAction: revisionAction,
              ),
            );
            if (licensesCompanion != null) {
              await _driveDao.insertLicense(licensesCompanion);
            }
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

  void emitErrorFromPreparation() {
    emit(UploadFailure(error: UploadErrors.unknown));
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

  Future<LicenseState?> _licenseStateForFileId(String? fileId) async {
    if (fileId != null) {
      final latestRevision = await _driveDao
          .latestFileRevisionByFileIdWithLicense(
            driveId: driveId,
            fileId: fileId,
          )
          .getSingleOrNull();
      if (latestRevision?.license != null) {
        final licenseCompanion = latestRevision!.license!.toCompanion(true);
        return _licenseService.fromCompanion(licenseCompanion);
      }
    }
    return null;
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
