import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/create_manifest/create_manifest_cubit.dart';
import 'package:ardrive/blocs/upload/models/models.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/upload_file_checker.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/core/upload/view/blocs/upload_manifest_options_bloc.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/models/forms/udl.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/is_custom_manifest.dart';
import 'package:ardrive/utils/leave_page_guard/leave_page_guard.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart'
    hide TurboUploadTimeoutException, TurboRateLimitException;
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'enums/conflicting_files_actions.dart';

part 'upload_state.dart';

final filesNamesToExclude = ['.DS_Store'];

enum UploadMethod { ar, turbo }

class UploadCubit extends Cubit<UploadState> {
  UploadCubit({
    required String driveId,
    required String parentFolderId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required UploadFileSizeChecker uploadFileSizeChecker,
    required ArDriveAuth auth,
    required ArDriveUploadPreparationManager arDriveUploadManager,
    required ActivityTracker activityTracker,
    required ConfigService configService,
    required UploadRepository uploadRepository,
    required ManifestRepository manifestRepository,
    required CreateManifestCubit createManifestCubit,
    bool uploadFolders = false,
    bool isDragNDrop = false,
    bool autoReplaceConflicts = false,
  })  : _isUploadFolders = uploadFolders,
        _isDragNDrop = isDragNDrop,
        _parentFolderId = parentFolderId,
        _driveId = driveId,
        _profileCubit = profileCubit,
        _uploadFileSizeChecker = uploadFileSizeChecker,
        _driveDao = driveDao,
        _auth = auth,
        _activityTracker = activityTracker,
        _uploadRepository = uploadRepository,
        _uploadThumbnail = configService.config.uploadThumbnails,
        _manifestRepository = manifestRepository,
        _createManifestCubit = createManifestCubit,
        _arDriveUploadManager = arDriveUploadManager,
        _autoReplaceConflicts = autoReplaceConflicts,
        super(uploadFolders ? UploadLoadingFolders() : UploadLoadingFiles());

  // Dependencies
  final UploadRepository _uploadRepository;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final UploadFileSizeChecker _uploadFileSizeChecker;
  final ArDriveAuth _auth;
  final ActivityTracker _activityTracker;
  final ManifestRepository _manifestRepository;
  final CreateManifestCubit _createManifestCubit;
  final ArDriveUploadPreparationManager _arDriveUploadManager;

  final String _driveId;
  final String _parentFolderId;
  final bool _isDragNDrop;
  final bool _autoReplaceConflicts;

  /// Utils for test
  @visibleForTesting
  bool isTest = false;

  /// Upload
  bool _hasEmittedWarning = false;
  bool _uploadIsInProgress = false;

  /// Pre-computed file lengths cache. Populated in parallel at the start of
  /// upload preparation to avoid redundant sequential file.ioFile.length reads.
  Map<String, int> _fileLengthCache = {};

  /// Target folder
  late Drive _targetDrive;
  late FolderEntry _targetFolder;
  late final bool _isUploadFolders;

  /// Manifest

  Map<String, UploadManifestModel> _manifestFiles = {};
  final List<ManifestSelection> _selectedManifestModels = [];

  UploadMethod? _manifestUploadMethod;

  bool _isManifestsUploadCancelled = false;

  /// if true, the file will change its content type to `application/x.arweave-manifest+json`
  bool _uploadFileAsCustomManifest = false;

  void updateManifestSelection(List<ManifestSelection> selections) {
    _selectedManifestModels.clear();

    _selectedManifestModels.addAll(selections);

    emit((state as UploadReady).copyWith(
      selectedManifestSelections: selections,
    ));
  }

  void setManifestUploadMethod(
      UploadMethod method, UploadPaymentMethodInfo info, bool canUpload) {
    _manifestUploadMethod = method;
  }

  void setIsUploadingCustomManifest(bool value) {
    _uploadFileAsCustomManifest = value;
    emit((state as UploadReady).copyWith(uploadFileAsCustomManifest: value));
  }

  Future<void> prepareManifestUpload() async {
    final freeAllowance = await _arDriveUploadManager.getFreeAllowance();
    final maxFreeItemBytes = _arDriveUploadManager.getMaxFreeItemBytes();

    final manifestModels = _selectedManifestModels
        .map((e) => UploadManifestModel(
              entry: e.manifest,
              freeThanksToTurbo: false,
              existingManifestFileId: e.manifest.id,
            ))
        .toList();

    for (int i = 0; i < manifestModels.length; i++) {
      if (_isManifestsUploadCancelled) {
        break;
      }

      manifestModels[i] = manifestModels[i].copyWith(isUploading: true);

      final manifestFileEntry = await _driveDao
          .fileById(fileId: manifestModels[i].existingManifestFileId)
          .getSingle();

      /// If the manifest has a fallback tx id, we need to reuse it
      await _createManifestCubit.prepareManifestTx(
        manifestName: manifestFileEntry.name,
        folderId: manifestFileEntry.parentFolderId,
        existingManifestFileId: manifestModels[i].existingManifestFileId,
      );

      final manifestFile =
          (_createManifestCubit.state as CreateManifestUploadReview)
              .manifestFile;

      manifestModels[i] = manifestModels[i].copyWith(file: manifestFile);

      final manifestSize = await manifestFile.length;

      /// Size alone is not enough: with the free allowance used up, every
      /// manifest here would be marked free, payment selection would be
      /// skipped entirely, and each upload would then fail with a 402.
      if (manifestSize <= maxFreeItemBytes &&
          freeAllowance.covers(manifestSize)) {
        manifestModels[i] = manifestModels[i].copyWith(freeThanksToTurbo: true);
      }
    }

    if (_isManifestsUploadCancelled) {
      return;
    }

    if (manifestModels.any((element) => !element.freeThanksToTurbo)) {
      emit(UploadManifestSelectPaymentMethod(
        files: manifestModels
            .map((e) =>
                UploadFile(ioFile: e.file!, parentFolderId: _targetFolder.id))
            .toList(),
        drive: _targetDrive,
        parentFolder: _targetFolder,
        manifestModels: manifestModels,
      ));

      return;
    }

    await uploadManifests(manifestModels);
  }

  Future<void> uploadManifests(List<UploadManifestModel> manifestModels) async {
    int completedCount = 0;

    for (int i = 0; i < manifestModels.length; i++) {
      if (_isManifestsUploadCancelled) {
        break;
      }

      manifestModels[i] = manifestModels[i].copyWith(isUploading: true);

      emit(UploadingManifests(
        manifestFiles: manifestModels,
        completedCount: completedCount,
      ));

      final manifestFileEntry = await _driveDao
          .fileById(fileId: manifestModels[i].existingManifestFileId)
          .getSingle();

      if (manifestFileEntry.fallbackTxId != null) {
        _createManifestCubit.setFallbackTxId(
          manifestFileEntry.fallbackTxId!,
          emitState: false,
        );
      }

      await _createManifestCubit.prepareManifestTx(
        manifestName: manifestFileEntry.name,
        folderId: manifestFileEntry.parentFolderId,
        existingManifestFileId: manifestModels[i].existingManifestFileId,
      );

      emit(UploadingManifests(
        manifestFiles: manifestModels,
        completedCount: completedCount,
      ));

      await _createManifestCubit.uploadManifest(method: _manifestUploadMethod);

      // Marked done here: only the name branch used to do it, so with no
      // name each deployment kept its spinner and the count stayed at 0.
      manifestModels[i] =
          manifestModels[i].copyWith(isUploading: false, isCompleted: true);
      emit(UploadingManifests(
        manifestFiles: manifestModels,
        completedCount: ++completedCount,
      ));
    }

    emit(UploadComplete(numberOfFiles: _files.length));
  }

  void cancelManifestsUpload() {
    _isManifestsUploadCancelled = true;
    emit(UploadComplete(numberOfFiles: _files.length));
  }

  /// License forms
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

  /// Upload settings
  List<UploadFile> _files = [];
  Map<String, WebFolder> _foldersByPath = {};
  UploadMethod? _uploadMethod;
  bool _uploadThumbnail;
  bool? _containsLargeTurboUpload;
  List<String> _paidBy = [];

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> _conflictingFiles = {};
  final List<String> _conflictingFolders = [];
  final List<String> _failedFiles = [];

  /// Thumbnail upload
  void changeUploadThumbnailOption(bool uploadThumbnail) {
    _uploadThumbnail = uploadThumbnail;
  }

  /// Whether this upload will make thumbnails for its images.
  bool get uploadThumbnail => _uploadThumbnail;

  /// Settings
  void showSettings() {
    emit((state as UploadReady).copyWith(showSettings: true));
  }

  void hideSettings() {
    emit((state as UploadReady).copyWith(showSettings: false));
  }

  /// Upload method
  void setUploadMethod(
    UploadMethod? method,
    UploadPaymentMethodInfo paymentInfo,
    bool canUpload,
  ) async {
    bool showSettings = _manifestFiles.isNotEmpty;

    _uploadMethod = method;
    _paidBy = paymentInfo.paidBy ?? [];

    logger
        .d('Setting upload method to $method with payment info: $paymentInfo');

    if (state is UploadReady) {
      final uploadReady = state as UploadReady;

      emit(uploadReady.copyWith(
        paymentInfo: paymentInfo,
        uploadMethod: method,
        isNextButtonEnabled: canUpload,
      ));
    } else if (state is UploadReadyToPrepare) {
      if (_targetDrive.isPublic && _files.length == 1) {
        final fileIsACustomManifest =
            await isCustomManifest(_files.first.ioFile);

        emit(
          UploadReady(
            params: (state as UploadReadyToPrepare)
                .params
                .copyWith(paidBy: paymentInfo.paidBy),
            paymentInfo: paymentInfo,
            numberOfFiles: _files.length,
            uploadIsPublic: !_targetDrive.isPrivate,
            isDragNDrop: _isDragNDrop,
            isNextButtonEnabled: canUpload,
            isArConnect: (state as UploadReadyToPrepare).isArConnect,
            totalSize: await _getTotalSize(),
            showSettings: showSettings,
            canShowSettings: showSettings,
            manifestFiles: _manifestFiles.values.toList(),
            showReviewButtonText: false,
            selectedManifestSelections: _selectedManifestModels,
            shouldShowCustomManifestCheckbox: fileIsACustomManifest,
            uploadFileAsCustomManifest: false,
          ),
        );
      } else {
        emit(
          UploadReady(
            params: (state as UploadReadyToPrepare)
                .params
                .copyWith(paidBy: paymentInfo.paidBy),
            paymentInfo: paymentInfo,
            numberOfFiles: _files.length,
            uploadIsPublic: !_targetDrive.isPrivate,
            isDragNDrop: _isDragNDrop,
            isNextButtonEnabled: canUpload,
            isArConnect: (state as UploadReadyToPrepare).isArConnect,
            totalSize: await _getTotalSize(),
            showSettings: showSettings,
            manifestFiles: _manifestFiles.values.toList(),
            canShowSettings: showSettings,
            showReviewButtonText: false,
            selectedManifestSelections: _selectedManifestModels,
            uploadFileAsCustomManifest: false,
            // only applies for single file uploads
            shouldShowCustomManifestCheckbox: false,
          ),
        );
      }
    }
  }

  void initialScreenUpload() {
    if (state is UploadReady) {
      if (_selectedManifestModels.isNotEmpty) {
        emit(UploadReview(readyState: state as UploadReady));
      } else {
        final readyState = state as UploadReady;
        startUpload(
          uploadPlanForAr: readyState.paymentInfo.uploadPlanForAR!,
          uploadPlanForTurbo: readyState.paymentInfo.uploadPlanForTurbo,
        );
      }
    }
  }

  Future<int> _getTotalSize() async {
    int size = 0;

    for (final file in _files) {
      size +=
          _fileLengthCache[file.getIdentifier()] ?? await file.ioFile.length;
    }

    return size;
  }

  void initialScreenNext({required LicenseCategory licenseCategory}) {
    if (state is UploadReady) {
      final readyState = state as UploadReady;
      emit(
        UploadConfiguringLicense(
          readyState: readyState,
          licenseCategory: licenseCategory,
        ),
      );
    }
  }

  /// License Settings
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
          final LicenseMeta? licenseMeta =
              _licenseCcTypeForm.control('ccTypeField').value;
          // No type is preselected, and Next stays disabled until one is
          // picked. If this is reached anyway, stay on this step.
          if (licenseMeta == null) return;
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
    } else if (state is UploadReview) {
      emit((state as UploadReview).readyState);
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
    } else if (state is UploadReview) {
      _startReviewedUpload();
    }
  }

  /// Conflict resolution
  Future<void> checkConflicts() async {
    if (_isUploadFolders) {
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
    if (_isUploadFolders) {
      final folderPrepareResult =
          await generateFoldersAndAssignParentsForFiles(_files);
      _files = folderPrepareResult.files;
      _foldersByPath = folderPrepareResult.foldersByPath;
    }
    for (final file in _files) {
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
        _conflictingFolders.add(existingFolderName);
      }
    }

    if (_conflictingFolders.isNotEmpty) {
      emit(
        UploadFolderNameConflict(
          areAllFilesConflicting: _conflictingFolders.length == _files.length,
          conflictingFileNames: _conflictingFolders,
        ),
      );
    } else {
      await checkConflictingFiles();
    }
  }

  Future<void> checkFilesAboveLimit() async {
    if (_isAPrivateUpload()) {
      final largeFiles =
          await _uploadFileSizeChecker.getFilesAboveSizeLimit(files: _files);

      if (largeFiles.isNotEmpty) {
        emit(
          UploadFileTooLarge(
            hasFilesToUpload: _files.length > largeFiles.length,
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

  Future<void> checkConflictingFiles({
    bool checkFailedFiles = true,
  }) async {
    emit(UploadPreparationInProgress());

    _removeFilesWithFolderNameConflicts();

    // Parallel conflict detection: check all files concurrently instead of
    // one sequential DB query per file.
    final conflictResults = await Future.wait(
      _files.map((file) async {
        final existingFileIds = await _driveDao
            .filesInFolderWithName(
              driveId: _targetDrive.id,
              parentFolderId: file.parentFolderId,
              name: file.ioFile.name,
            )
            .map((f) => f.id)
            .get();
        return (file: file, existingIds: existingFileIds);
      }),
    );

    for (final result in conflictResults) {
      if (result.existingIds.isNotEmpty) {
        final existingFileId = result.existingIds.first;
        logger.d('Found conflicting file. Existing file id: $existingFileId');
        _conflictingFiles[result.file.getIdentifier()] = existingFileId;
      }
    }

    if (_conflictingFiles.isNotEmpty) {
      // Auto-replace conflicts when flag is set (used for markdown editing)
      if (_autoReplaceConflicts) {
        logger.d(
            'Auto-replacing ${_conflictingFiles.length} conflicting file(s)');
        await prepareUploadPlanAndCostEstimates(
          uploadAction: UploadActions.replace,
        );
        return;
      }

      if (checkFailedFiles) {
        _failedFiles.clear();

        _conflictingFiles.forEach((key, value) {
          logger.d('Checking if file $key has failed');
        });

        for (final fileNameKey in _conflictingFiles.keys) {
          final fileId = _conflictingFiles[fileNameKey];

          final fileRevision = await _driveDao
              .latestFileRevisionByFileId(
                driveId: _driveId,
                fileId: fileId!,
              )
              .getSingleOrNull();

          final status = _driveDao.select(_driveDao.networkTransactions)
            ..where((tbl) => tbl.id.equals(fileRevision!.dataTxId));

          final transaction = await status.getSingleOrNull();

          logger.d('Transaction status: ${transaction?.status}');

          if (transaction?.status == TransactionStatus.failed) {
            _failedFiles.add(fileNameKey);
          }
        }

        logger.d('Failed files: $_failedFiles');

        if (_failedFiles.isNotEmpty) {
          emit(
            UploadConflictWithFailedFiles(
              areAllFilesConflicting: _conflictingFiles.length == _files.length,
              conflictingFileNames: _conflictingFiles.keys.toList(),
              conflictingFileNamesForFailedFiles: _failedFiles,
            ),
          );
          return;
        }
      }

      emit(
        UploadFileConflict(
          areAllFilesConflicting: _conflictingFiles.length == _files.length,
          conflictingFileNames: _conflictingFiles.keys.toList(),
          conflictingFileNamesForFailedFiles: const [],
        ),
      );
    } else {
      await prepareUploadPlanAndCostEstimates();
    }
  }

  Future<void> verifyFilesAboveWarningLimit() async {
    emit(UploadPreparationInProgress());

    // Yield to allow the UI to render UploadPreparationInProgress before
    // starting potentially heavy computation.
    await Future.delayed(Duration.zero);

    if (!_targetDrive.isPrivate) {
      if (await _uploadFileSizeChecker.hasFileAboveWarningSizeLimit(
          files: _files)) {
        emit(UploadShowingWarning(
          uploadPlanForAR: null,
          uploadPlanForTurbo: null,
        ));

        return;
      }
    }

    checkFilesAboveLimit();
  }

  Future<void> skipLargeFilesAndCheckForConflicts() async {
    emit(UploadPreparationInProgress());
    final List<String> filesToSkip =
        await _uploadFileSizeChecker.getFilesAboveSizeLimit(files: _files);

    _files.removeWhere(
      (file) => filesToSkip.contains(file.getIdentifier()),
    );

    await checkConflicts();
  }

  /// Upload Preparation
  Future<void> pickFiles({
    required BuildContext context,
    required String parentFolderId,
  }) async {
    try {
      final files = await _uploadRepository.pickFiles(
          context: context, parentFolderId: parentFolderId);
      if (files.isEmpty) {
        emit(EmptyUpload());
        return;
      }
      _files.addAll(files);
      emit(UploadLoadingFilesSuccess());
    } catch (e) {
      if (e is ActionCanceledException) {
        emit(EmptyUpload());
      } else {
        _emitError(e);
      }
    }
  }

  Future<void> pickFilesFromFolder({
    required BuildContext context,
    required String parentFolderId,
  }) async {
    try {
      final files = await _uploadRepository.pickFilesFromFolder(
          context: context, parentFolderId: parentFolderId);
      if (files.isEmpty) {
        emit(EmptyUpload());
        return;
      }

      _files.addAll(files);

      logger.d('Upload preparation started. Number of files: ${_files.length}');
      emit(UploadLoadingFilesSuccess());
    } catch (e) {
      if (e is ActionCanceledException) {
        emit(EmptyUpload());
      } else {
        _emitError(e);
      }
    }
  }

  void selectFiles(List<IOFile> files, String parentFolderId) {
    _files.addAll(files.map((file) {
      return UploadFile(
        ioFile: file,
        parentFolderId: parentFolderId,
      );
    }));

    emit(UploadLoadingFilesSuccess());
  }

  Future<void> startUploadPreparation({
    bool isRetryingToPayWithTurbo = false,
  }) async {
    _files
        .removeWhere((file) => filesNamesToExclude.contains(file.ioFile.name));
    _targetDrive = await _driveDao.driveById(driveId: _driveId).getSingle();
    _targetFolder =
        await _driveDao.folderById(folderId: _parentFolderId).getSingle();

    // Pre-compute all file lengths in parallel to avoid redundant sequential
    // reads across warning check, conflict detection, and plan creation.
    final lengths = await Future.wait(
      _files.map((f) async => await f.ioFile.length),
    );
    _fileLengthCache = {
      for (var i = 0; i < _files.length; i++)
        _files[i].getIdentifier(): lengths[i],
    };

    // TODO: check if the backend refreshed the balance instead of a timer
    if (isRetryingToPayWithTurbo) {
      emit(UploadPreparationInProgress());

      /// necessary to wait for backend update the balance
      await Future.delayed(const Duration(seconds: 2));
    }

    logger.d('Upload preparation started. Number of files: ${_files.length}');

    /// When the number of files is less than 100, we show a loading indicator
    /// More than that, we don't show it, because it would be too slow
    emit(UploadPreparationInitialized(showLoadingFiles: _files.length < 100));

    if (!isTest) {
      await verifyFilesAboveWarningLimit();
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
            driveId: _driveId,
            name: folder.name,
            parentFolderId: folder.parentFolderId,
          )
          .map((f) => f.id)
          .getSingleOrNull();
      final existingFileIds = await _driveDao
          .filesInFolderWithName(
            driveId: _driveId,
            name: folder.name,
            parentFolderId: folder.parentFolderId,
          )
          .map((f) => f.id)
          .get();

      if (existingFolderId != null) {
        folder.id = existingFolderId;
        foldersToSkip.add(folder);
      }
      if (existingFileIds.isNotEmpty) {
        _conflictingFolders.add(folder.name);
      }
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
    } else if (uploadAction == UploadActions.skipSuccessfulUploads) {
      _removeSuccessfullyUploadedFiles();
    }

    logger.d(
      'Upload preparation started. UploadMethod: $_uploadMethod',
    );

    try {
      final containsSupportedImageTypeForThumbnailGeneration = _files.any(
        (element) => supportedImageTypesInFilePreview.contains(
          element.ioFile.contentType,
        ),
      );

      final manifestFileEntries =
          await _manifestRepository.getManifestFilesInFolder(
        folderId: _targetFolder.id,
        driveId: _targetDrive.id,
      );

      _manifestFiles = {};

      final manifestFreeAllowance =
          await _arDriveUploadManager.getFreeAllowance();
      final manifestMaxFreeItemBytes =
          _arDriveUploadManager.getMaxFreeItemBytes();

      for (var entry in manifestFileEntries) {
        _manifestFiles[entry.id] = UploadManifestModel(
          entry: entry,
          existingManifestFileId: entry.id,
          // Free requires both a small enough item and allowance to cover it.
          // The size limit comes from the upload manager, which prefers
          // Turbo's server-reported value over the static config one.
          freeThanksToTurbo: entry.size <= manifestMaxFreeItemBytes &&
              manifestFreeAllowance.covers(entry.size),
        );
      }

      // if there are no files that can be used to generate a thumbnail, we disable the option
      if (!containsSupportedImageTypeForThumbnailGeneration) {
        _uploadThumbnail = false;
      }

      emit(
        UploadReadyToPrepare(
          params: UploadParams(
            user: _auth.currentUser,
            files: _files,
            targetFolder: _targetFolder,
            targetDrive: _targetDrive,
            conflictingFiles: _conflictingFiles,
            foldersByPath: _foldersByPath,
            containsSupportedImageTypeForThumbnailGeneration:
                containsSupportedImageTypeForThumbnailGeneration,
          ),
          isArConnect: await _profileCubit.isCurrentProfileArConnect(),
        ),
      );
    } catch (error, stacktrace) {
      logger.e('error mounting the upload', error, stacktrace);
      _emitError(error);
    }
  }

  void emitErrorFromPreparation() {
    emit(UploadFailure(error: UploadErrors.unknown));
  }

  /// Upload
  void _startReviewedUpload() {
    final review = state as UploadReview;

    startUpload(
      uploadPlanForAr: review.readyState.paymentInfo.uploadPlanForAR!,
      uploadPlanForTurbo: review.readyState.paymentInfo.uploadPlanForTurbo,
    );
  }

  Future<void> startUpload({
    required UploadPlan uploadPlanForAr,
    UploadPlan? uploadPlanForTurbo,
    LicenseState? licenseStateConfigured,
  }) async {
    if (_uploadIsInProgress) {
      return;
    }

    if (_uploadFileAsCustomManifest) {
      final fileWithCustomContentType = await IOFile.fromData(
        await _files.first.ioFile.readAsBytes(),
        name: _files.first.ioFile.name,
        lastModifiedDate: _files.first.ioFile.lastModifiedDate,
        contentType: ContentType.manifest,
      );

      _files.first = UploadFile(
        ioFile: fileWithCustomContentType,
        parentFolderId: _files.first.parentFolderId,
        relativeTo: _files.first.relativeTo,
      );
    }

    _uploadIsInProgress = true;

    UploadPlan uploadPlan;

    if (_uploadMethod == UploadMethod.ar || uploadPlanForTurbo == null) {
      uploadPlan = uploadPlanForAr;
    } else {
      uploadPlan = uploadPlanForTurbo;
    }

    logger.d('Max files per bundle: ${uploadPlan.maxDataItemCount}');
    logger.d('Upload plan: $uploadPlan');

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
    final UploadContains contains = _isUploadFolders
        ? UploadContains.folder
        : _files.length == 1
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
      if ((_containsLargeTurboUpload ?? false) && !_hasEmittedWarning) {
        emit(
          UploadShowingWarning(
            uploadPlanForAR: uploadPlanForAr,
            uploadPlanForTurbo: uploadPlanForTurbo,
          ),
        );
        _hasEmittedWarning = true;
        return;
      }
    } else {
      _containsLargeTurboUpload = false;
    }

    if (_isUploadFolders) {
      await _uploadFolders(
        licenseStateConfigured: licenseStateConfigured,
      );
      return;
    }

    await _uploadFiles(
      licenseStateConfigured: licenseStateConfigured,
    );

    return;
  }

  /// Whether a retry is starting, so a second press does nothing.
  bool _retrying = false;

  /// Sends the failed files again. It waits for whatever is left of the
  /// attempt before to stop, so nothing is sent or paid for twice, and a
  /// second press while it starts is ignored.
  Future<void> retryUploads() async {
    final current = state;
    if (_retrying || current is! UploadFailure) return;
    final controller = current.controller;
    if (controller == null) return;
    _retrying = true;
    emit(UploadPreparationInProgress());
    try {
      await controller.retryFailedTasks(_auth.currentUser.wallet);
    } finally {
      _retrying = false;
    }
  }

  /// Upload, pressed on the review: paid the way the review showed, whatever
  /// the payment sheet last defaulted to, which can be the wallet when credits
  /// are short or Turbo is down. Goes on to the license step when there is
  /// one, the manifest review when manifests are chosen, or the upload.
  void uploadFromReview({
    required UploadMethod method,
    LicenseCategory? licenseCategory,
  }) {
    _uploadMethod = method;
    if (licenseCategory != null) {
      initialScreenNext(licenseCategory: licenseCategory);
    } else {
      initialScreenUpload();
    }
  }

  /// How this upload will be paid for.
  @visibleForTesting
  UploadMethod? get uploadMethod => _uploadMethod;

  /// Set once the person cancels. A canceled upload is never reported
  /// complete, so it never says the files are saved.
  bool _uploadCanceled = false;

  Future<void> cancelUpload() async {
    if (state is UploadInProgress) {
      _uploadCanceled = true;
      try {
        final state = this.state as UploadInProgress;

        emit(
          UploadInProgress(
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
          UploadInProgress(
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

  Future<void> _uploadFolders({
    LicenseState? licenseStateConfigured,
  }) async {
    _activityTracker.setUploading(true);

    final uploadController = await _uploadRepository.uploadFolders(
      files: _files,
      targetDrive: _targetDrive,
      conflictingFiles: _conflictingFiles,
      targetFolder: _targetFolder,
      uploadMethod: _uploadMethod!,
      conflictingFolders: _conflictingFolders,
      foldersByPath: _foldersByPath,
      licenseStateConfigured: licenseStateConfigured,
      uploadThumbnail: _uploadThumbnail,
      paidBy: _paidBy,
    );

    uploadController.onError((tasks) {
      logger.i('Error uploading folders. Number of tasks: ${tasks.length}');
      emit(UploadFailure(
          error: _uploadErrorFromTasks(tasks),
          failedTasks: tasks,
          controller: uploadController));
    });

    uploadController.onFailedTask((task) {
      logger.e('UploadTask failed. Task: ${task.errorInfo()}', task.error);
    });

    uploadController.onProgressChange(
      (progress) {
        emit(
          UploadInProgress(
            totalProgress: progress.progressInPercentage,
            equatableBust: UniqueKey(),
            progress: progress,
            controller: uploadController,
            uploadMethod: _uploadMethod!,
          ),
        );
      },
    );

    uploadController.onDone(
      (tasks) async {
        if (_uploadCanceled) return;
        if (_selectedManifestModels.isNotEmpty) {
          await prepareManifestUpload();
        }

        emit(UploadComplete(numberOfFiles: _files.length));

        unawaited(_profileCubit.refreshBalance());
      },
    );
  }

  Future<void> _uploadFiles({
    LicenseState? licenseStateConfigured,
  }) async {
    _activityTracker.setUploading(true);

    /// Creates the uploader and starts the upload.
    final uploadController = await _uploadRepository.uploadFiles(
      files: _files,
      targetDrive: _targetDrive,
      conflictingFiles: _conflictingFiles,
      licenseStateConfigured: licenseStateConfigured,
      targetFolder: _targetFolder,
      uploadMethod: _uploadMethod!,
      uploadThumbnail: _uploadThumbnail,
      paidBy: _paidBy,
    );

    uploadController.onError((tasks) {
      logger.i('Error uploading files. Number of tasks: ${tasks.length}');
      emit(
        UploadFailure(
          error: _uploadErrorFromTasks(tasks),
          failedTasks: tasks,
          controller: uploadController,
        ),
      );
    });

    uploadController.onFailedTask((task) {
      logger.e('UploadTask failed. Task: ${task.errorInfo()}', task.error);
    });

    uploadController.onProgressChange(
      (progress) async {
        emit(
          UploadInProgress(
            progress: progress,
            totalProgress: progress.progressInPercentage,
            controller: uploadController,
            equatableBust: UniqueKey(),
            uploadMethod: _uploadMethod!,
          ),
        );
      },
    );

    // TODO: implement on the upload repository
    uploadController.onDone(
      (tasks) async {
        if (_uploadCanceled) return;
        unawaited(_profileCubit.refreshBalance());

        logger.i(
          'Upload finished with success. Number of tasks: ${tasks.length}',
        );

        if (_selectedManifestModels.isNotEmpty) {
          await prepareManifestUpload();
        }

        final uploaded = [
          for (final task in tasks)
            for (final item in task.content ?? const [])
              if (item is ARFSFileUploadMetadata) item,
        ];
        emit(UploadComplete(
          dataTxIds: [for (final item in uploaded) item.dataTxId!],
          fileIds: [for (final item in uploaded) item.id],
          numberOfFiles: _files.length,
        ));

        PlausibleEventTracker.trackUploadSuccess();
      },
    );
  }

  Future<void> _verifyIfUploadContainsLargeFilesUsingTurbo() async {
    if (_containsLargeTurboUpload == null) {
      _containsLargeTurboUpload = false;

      if (await _uploadFileSizeChecker.hasFileAboveSizeLimit(files: _files)) {
        _containsLargeTurboUpload = true;
        return;
      }
    }
  }

  void _removeFilesWithFileNameConflicts() {
    _files.removeWhere(
      (file) => _conflictingFiles.containsKey(file.getIdentifier()),
    );
  }

  void _removeSuccessfullyUploadedFiles() {
    _files.removeWhere(
      (file) => !_failedFiles.contains(file.getIdentifier()),
    );
  }

  void _removeFilesWithFolderNameConflicts() {
    _files
        .removeWhere((file) => _conflictingFolders.contains(file.ioFile.name));
  }

  @visibleForTesting
  bool isPrivateForTesting = false;

  bool _isAPrivateUpload() {
    return isPrivateForTesting || _targetDrive.isPrivate;
  }

  void _emitError(Object error) {
    if (error is TurboUploadTimeoutException) {
      emit(UploadFailure(error: UploadErrors.turboTimeout));

      return;
    }

    if (isTurboPaymentError(error)) {
      emit(UploadFailure(error: UploadErrors.turboPaymentRequired));

      return;
    }

    emit(UploadFailure(error: UploadErrors.unknown));
  }

  /// Classifies a failed-task list from the uploader into an [UploadErrors].
  /// A payment rejection (free allowance exhausted / insufficient credits)
  /// arrives as an UnderFundException on one of the tasks.
  UploadErrors _uploadErrorFromTasks(List<UploadTask> tasks) {
    final hasPaymentError = tasks.any((t) => isTurboPaymentError(t.error));
    return hasPaymentError
        ? UploadErrors.turboPaymentRequired
        : UploadErrors.unknown;
  }

  /// Keeps the browser asking before the tab is closed while an upload paid
  /// from the wallet can still be lost by closing it: while it runs, and while
  /// its failed files can still be re-uploaded. Such an upload pays for its
  /// transaction before sending its data, and only this tab holds what is
  /// needed to send the data, so closing it then leaves a paid transaction
  /// with nothing in it.
  /// The upload as it was last reviewed, for asking for Turbo Credits after
  /// Turbo refused it: the files, and what they cost.
  UploadReady? get lastReadyState => _lastReadyState;
  UploadReady? _lastReadyState;

  @override
  void onChange(Change<UploadState> change) {
    super.onChange(change);
    final next = change.nextState;
    if (next is UploadReady) _lastReadyState = next;
    if (isWalletPaidUploadAtRisk(change.nextState)) {
      holdLeavePageGuard(this);
    } else {
      releaseLeavePageGuard(this);
    }
  }

  @override
  Future<void> close() {
    releaseLeavePageGuard(this);
    return super.close();
  }
}

/// Whether [state] is an upload paid from the wallet that closing the tab
/// would lose: one in progress, or one with failed files left to re-upload.
bool isWalletPaidUploadAtRisk(UploadState state) {
  if (state is UploadInProgress) {
    return state.uploadMethod == UploadMethod.ar;
  }
  if (state is UploadFailure) {
    return state.failedTasks?.any((t) => t.type == UploadType.d2n) ?? false;
  }
  return false;
}

class UploadFolder extends IOFolder {
  UploadFolder({
    required this.name,
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
  // We dont need to use the path for the upload
  final String path = '';

  @override
  List<Object?> get props => [name, path, lastModifiedDate];
}
