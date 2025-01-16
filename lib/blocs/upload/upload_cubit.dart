import 'dart:async';

import 'package:ardrive/arns/domain/arns_repository.dart';
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
import 'package:ardrive/main.dart';
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
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/upload_plan_utils.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ario_sdk/ario_sdk.dart';
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
    required ARNSRepository arnsRepository,
    required UploadRepository uploadRepository,
    required ManifestRepository manifestRepository,
    required CreateManifestCubit createManifestCubit,
    bool uploadFolders = false,
    bool isDragNDrop = false,
  })  : _isUploadFolders = uploadFolders,
        _isDragNDrop = isDragNDrop,
        _parentFolderId = parentFolderId,
        _driveId = driveId,
        _profileCubit = profileCubit,
        _uploadFileSizeChecker = uploadFileSizeChecker,
        _driveDao = driveDao,
        _auth = auth,
        _activityTracker = activityTracker,
        _arnsRepository = arnsRepository,
        _uploadRepository = uploadRepository,
        _uploadThumbnail = configService.config.uploadThumbnails,
        _manifestRepository = manifestRepository,
        _createManifestCubit = createManifestCubit,
        super(uploadFolders ? UploadLoadingFolders() : UploadLoadingFiles());

  // Dependencies
  final UploadRepository _uploadRepository;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final UploadFileSizeChecker _uploadFileSizeChecker;
  final ArDriveAuth _auth;
  final ActivityTracker _activityTracker;
  final ARNSRepository _arnsRepository;
  final ManifestRepository _manifestRepository;
  final CreateManifestCubit _createManifestCubit;

  final String _driveId;
  final String _parentFolderId;
  final bool _isDragNDrop;

  /// Utils for test
  @visibleForTesting
  bool isTest = false;

  /// Upload
  bool _hasEmittedWarning = false;
  bool _uploadIsInProgress = false;

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
    final manifestModels = _selectedManifestModels
        .map((e) => UploadManifestModel(
              entry: e.manifest,
              freeThanksToTurbo: false,
              existingManifestFileId: e.manifest.id,
              antRecord: e.antRecord,
              undername: e.undername,
            ))
        .toList();

    for (int i = 0; i < manifestModels.length; i++) {
      if (_isManifestsUploadCancelled) {
        break;
      }

      manifestModels[i] = manifestModels[i].copyWith(isUploading: true);

      final manifestFileEntry = await _driveDao
          .fileById(
            driveId: _driveId,
            fileId: manifestModels[i].existingManifestFileId,
          )
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

      if (manifestSize <= configService.config.allowedDataItemSizeForTurbo) {
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
          .fileById(
            driveId: _driveId,
            fileId: manifestModels[i].existingManifestFileId,
          )
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

      final manifestFile = await _driveDao
          .fileById(
            driveId: _driveId,
            fileId: manifestModels[i].existingManifestFileId,
          )
          .getSingleOrNull();

      if (manifestFile == null) {
        throw StateError('Manifest file not found');
      }

      if (manifestModels[i].antRecord != null) {
        ARNSUndername undername;

        if (manifestModels[i].undername == null) {
          undername = ARNSUndername(
            name: '@',
            domain: manifestModels[i].antRecord!.domain,
            record: ARNSRecord(
              transactionId: manifestFile.dataTxId,
              ttlSeconds: 3600,
            ),
          );
        } else {
          undername = ARNSUndername(
            name: manifestModels[i].undername!.name,
            domain: manifestModels[i].antRecord!.domain,
            record: ARNSRecord(
              transactionId: manifestFile.dataTxId,
              ttlSeconds: 3600,
            ),
          );
        }

        manifestModels[i] = manifestModels[i].copyWith(
            isCompleted: false, isUploading: false, isAssigningUndername: true);
        emit(UploadingManifests(
          manifestFiles: manifestModels,
          completedCount: ++completedCount,
        ));

        await _arnsRepository.setUndernamesToFile(
          undername: undername,
          driveId: _driveId,
          fileId: manifestModels[i].existingManifestFileId,
          processId: manifestModels[i].antRecord!.processId,
        );

        manifestModels[i] = manifestModels[i].copyWith(
            isCompleted: true, isUploading: false, isAssigningUndername: false);

        emit(UploadingManifests(
          manifestFiles: manifestModels,
          completedCount: completedCount,
        ));
      }
    }

    emit(UploadComplete());
  }

  void cancelManifestsUpload() {
    _isManifestsUploadCancelled = true;
    emit(UploadComplete());
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
  bool _showArnsNameSelectionCheckBoxValue = false;
  bool? _containsLargeTurboUpload;

  /// Map of conflicting file ids keyed by their file names.
  final Map<String, String> _conflictingFiles = {};
  final List<String> _conflictingFolders = [];
  final List<String> _failedFiles = [];

  /// ArNS
  ANTRecord? _selectedAntRecord;
  List<ANTRecord> _ants = [];
  ARNSUndername? _selectedUndername;

  /// Thumbnail upload
  void changeUploadThumbnailOption(bool uploadThumbnail) {
    _uploadThumbnail = uploadThumbnail;
  }

  /// Settings
  void showSettings() {
    emit((state as UploadReady).copyWith(showSettings: true));
  }

  void hideSettings() {
    emit((state as UploadReady).copyWith(showSettings: false));
  }

  /// ArNS name selection
  void selectUndernameWithLicense({
    ANTRecord? antRecord,
    ARNSUndername? undername,
  }) {
    _selectedAntRecord = antRecord;
    _selectedUndername = undername;

    final reviewWithLicense = state as UploadReviewWithLicense;

    final params = reviewWithLicense.readyState.params.copyWith(
      arnsUnderName: _getSelectedUndername(),
    );

    final readyState = reviewWithLicense.readyState.copyWith(
      params: params,
      showArnsNameSelection: false,
    );

    emit(reviewWithLicense.copyWith(readyState: readyState));
  }

  void selectUndername(ANTRecord? antRecord, ARNSUndername? undername) {
    _selectedAntRecord = antRecord;
    _selectedUndername = undername;

    final readyState = (state as UploadReady).copyWith(
      params: (state as UploadReady).params.copyWith(
            arnsUnderName: _getSelectedUndername(),
          ),
    );

    emit(UploadReview(readyState: readyState));
  }

  void changeShowArnsNameSelection(bool showArnsNameSelection) {
    _showArnsNameSelectionCheckBoxValue = showArnsNameSelection;

    if (state is UploadReady) {
      final readyState = state as UploadReady;
      emit(readyState.copyWith(arnsCheckboxChecked: showArnsNameSelection));
    }
  }

  void showArnsNameSelection(UploadReady readyState) {
    emit(readyState.copyWith(showArnsNameSelection: true));
  }

  void hideArnsNameSelection(UploadReady readyState) {
    emit(readyState.copyWith(showArnsNameSelection: false));
  }

  void cancelArnsNameSelection() {
    if (state is UploadReady) {
      logger.d('Cancelling ARNS name selection');

      final readyState = state as UploadReady;

      _showArnsNameSelectionCheckBoxValue = false;

      emit(readyState.copyWith(
        showArnsNameSelection: false,
        loadingArNSNames: false,
        loadingArNSNamesError: false,
        showArnsCheckbox: true,
      ));
    } else if (state is UploadReviewWithLicense) {
      final reviewWithLicense = state as UploadReviewWithLicense;
      final readyState = reviewWithLicense.readyState.copyWith(
        showArnsNameSelection: false,
        loadingArNSNames: false,
        loadingArNSNamesError: false,
        showArnsCheckbox: true,
      );
      emit(readyState);
    }
  }

  /// Upload method
  void setUploadMethod(
    UploadMethod? method,
    UploadPaymentMethodInfo paymentInfo,
    bool canUpload,
  ) async {
    bool showSettings = _manifestFiles.isNotEmpty;

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
      bool showArnsCheckbox = false;

      if (_targetDrive.isPublic && _files.length == 1) {
        final fileIsACustomManifest =
            await isCustomManifest(_files.first.ioFile);

        emit(
          UploadReady(
            params: (state as UploadReadyToPrepare).params,
            paymentInfo: paymentInfo,
            numberOfFiles: _files.length,
            uploadIsPublic: !_targetDrive.isPrivate,
            isDragNDrop: _isDragNDrop,
            isNextButtonEnabled: canUpload,
            isArConnect: (state as UploadReadyToPrepare).isArConnect,
            showArnsCheckbox: showArnsCheckbox,
            showArnsNameSelection: false,
            loadingArNSNames: true,
            arnsCheckboxChecked: _showArnsNameSelectionCheckBoxValue,
            totalSize: await _getTotalSize(),
            showSettings: showSettings,
            canShowSettings: showSettings,
            manifestFiles: _manifestFiles.values.toList(),
            arnsRecords: _ants,
            showReviewButtonText: false,
            selectedManifestSelections: _selectedManifestModels,
            shouldShowCustomManifestCheckbox: fileIsACustomManifest,
            uploadFileAsCustomManifest: false,
          ),
        );

        try {
          final hasUndernames = (await _arnsRepository
                  .getAntRecordsForWallet(_auth.currentUser.walletAddress))
              .isNotEmpty;

          showArnsCheckbox = hasUndernames;

          if (state is! UploadReady) {
            logger.d('State is not UploadReady');
            return;
          }

          final readyState = state as UploadReady;

          emit(readyState.copyWith(
              loadingArNSNames: false, showArnsCheckbox: showArnsCheckbox));
        } catch (e) {
          if (state is UploadReady) {
            final readyState = state as UploadReady;
            emit(readyState.copyWith(
                loadingArNSNamesError: true, loadingArNSNames: false));
          }
        }
      } else {
        emit(
          UploadReady(
            params: (state as UploadReadyToPrepare).params,
            paymentInfo: paymentInfo,
            numberOfFiles: _files.length,
            uploadIsPublic: !_targetDrive.isPrivate,
            isDragNDrop: _isDragNDrop,
            isNextButtonEnabled: canUpload,
            isArConnect: (state as UploadReadyToPrepare).isArConnect,
            showArnsCheckbox: showArnsCheckbox,
            showArnsNameSelection: false,
            arnsCheckboxChecked: _showArnsNameSelectionCheckBoxValue,
            totalSize: await _getTotalSize(),
            showSettings: showSettings,
            manifestFiles: _manifestFiles.values.toList(),
            arnsRecords: _ants,
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
      if (_showArnsNameSelectionCheckBoxValue) {
        showArnsNameSelection(state as UploadReady);
      } else if (_selectedManifestModels.isNotEmpty) {
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
      size += await file.ioFile.length;
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
          final LicenseMeta licenseMeta =
              _licenseCcTypeForm.control('ccTypeField').value;
          licenseState = LicenseState(meta: licenseMeta);
        default:
          throw StateError(
              'Invalid license category: ${configuringLicense.licenseCategory}');
      }

      final readyState = configuringLicense.readyState.copyWith(
        showArnsNameSelection: _showArnsNameSelectionCheckBoxValue,
      );

      emit(UploadReviewWithLicense(
        readyState: readyState,
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
      final reviewWithArnsName = state as UploadReview;
      final readyState = reviewWithArnsName.readyState.copyWith(
        showArnsNameSelection: false,
      );

      emit(readyState);
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
      startUploadWithArnsName();
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

    for (final file in _files) {
      final fileName = file.ioFile.name;
      final existingFileIds = await _driveDao
          .filesInFolderWithName(
            driveId: _targetDrive.id,
            parentFolderId: file.parentFolderId,
            name: fileName,
          )
          .map((f) => f.id)
          .get();

      if (existingFileIds.isNotEmpty) {
        final existingFileId = existingFileIds.first;

        logger.d('Found conflicting file. Existing file id: $existingFileId');
        _conflictingFiles[file.getIdentifier()] = existingFileId;
      }
    }

    if (_conflictingFiles.isNotEmpty) {
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

    /// This delay is necessary. Once we start the upload checks, we will perform high computational tasks.
    /// This delay ensures the previous state (UploadPreparationInProgress) is updated before starting the upload checks.
    await Future.delayed(const Duration(milliseconds: 100));

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

  Future<List<ARNSUndername>> getARNSUndernames(
    ANTRecord antRecord,
  ) async {
    return _arnsRepository.getARNSUndernames(antRecord);
  }

  Future<void> startUploadPreparation({
    bool isRetryingToPayWithTurbo = false,
  }) async {
    final walletAddress = await _auth.getWalletAddress();
    _arnsRepository.getAntRecordsForWallet(walletAddress!).then((value) {
      _ants = value;
      if (state is UploadReady) {
        emit((state as UploadReady).copyWith(arnsRecords: value));
      }
    }).catchError((e) {
      logger.e(
          'Error getting ant records for wallet. Proceeding with the upload...',
          e);
    });

    _files
        .removeWhere((file) => filesNamesToExclude.contains(file.ioFile.name));
    _targetDrive = await _driveDao.driveById(driveId: _driveId).getSingle();
    _targetFolder = await _driveDao
        .folderById(driveId: _driveId, folderId: _parentFolderId)
        .getSingle();

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
      if (await _profileCubit.checkIfWalletMismatch()) {
        emit(UploadWalletMismatch());
        return;
      }

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

      for (var entry in manifestFileEntries) {
        _manifestFiles[entry.id] = UploadManifestModel(
          entry: entry,
          existingManifestFileId: entry.id,
          freeThanksToTurbo:
              entry.size <= configService.config.allowedDataItemSizeForTurbo,
        );
      }

      // if there are no files that can be used to generate a thumbnail, we disable the option
      if (!containsSupportedImageTypeForThumbnailGeneration) {
        _uploadThumbnail = false;
      }

      if (manifestFileEntries.isNotEmpty) {
        try {
          await _arnsRepository
              .getAntRecordsForWallet(_auth.currentUser.walletAddress);
        } catch (e) {
          logger.e(
              'Error getting ant records for wallet. Proceeding with the upload...',
              e);
        }
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
  void startUploadWithArnsName() {
    final reviewWithArnsName = state as UploadReview;

    startUpload(
      uploadPlanForAr:
          reviewWithArnsName.readyState.paymentInfo.uploadPlanForAR!,
      uploadPlanForTurbo:
          reviewWithArnsName.readyState.paymentInfo.uploadPlanForTurbo,
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

  void retryUploads() {
    if (state is UploadFailure) {
      final controller = (state as UploadFailure).controller!;

      controller.retryFailedTasks(_auth.currentUser.wallet);
    }
  }

  Future<void> cancelUpload() async {
    if (state is UploadInProgress) {
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
      assignedName: _files.length == 1 && _getSelectedUndername() != null
          ? getLiteralARNSRecordName(_getSelectedUndername()!)
          : null,
    );

    uploadController.onError((tasks) {
      logger.i('Error uploading folders. Number of tasks: ${tasks.length}');
      emit(UploadFailure(
          error: UploadErrors.unknown,
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
        /// If there is only one file in the upload, we assign the undername if any assigned
        if (tasks.whereType<FileUploadTask>().length == 1) {
          final task = tasks.whereType<FileUploadTask>().first;
          await _postUploadFile(
            task: task,
            uploadController: uploadController,
          );
        }

        if (_selectedManifestModels.isNotEmpty) {
          await prepareManifestUpload();
        }

        emit(UploadComplete());

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
      assignedName: _getSelectedUndername() != null
          ? getLiteralARNSRecordName(_getSelectedUndername()!)
          : null,
    );

    uploadController.onError((tasks) {
      logger.i('Error uploading files. Number of tasks: ${tasks.length}');
      emit(
        UploadFailure(
          error: UploadErrors.unknown,
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
        /// If there is only one file in the upload, we assign the undername if any assigned
        if (tasks.length == 1) {
          if (tasks.first is FileUploadTask) {
            await _postUploadFile(
              task: tasks.first as FileUploadTask,
              uploadController: uploadController,
            );
          }
        }

        unawaited(_profileCubit.refreshBalance());

        logger.i(
          'Upload finished with success. Number of tasks: ${tasks.length}',
        );

        if (_selectedManifestModels.isNotEmpty) {
          await prepareManifestUpload();
        }

        emit(UploadComplete());

        PlausibleEventTracker.trackUploadSuccess();
      },
    );
  }

  Future<void> _postUploadFile({
    required FileUploadTask task,
    required UploadController uploadController,
  }) async {
    if (task.status != UploadStatus.canceled) {
      final metadata = task.metadata;
      if (_selectedAntRecord != null || _selectedUndername != null) {
        final updatedTask = task.copyWith(
          status: UploadStatus.assigningUndername,
        );

        /// Emits
        emit(
          UploadInProgress(
            progress: UploadProgress(
              progressInPercentage: 1,
              numberOfItems: 1,
              numberOfUploadedItems: 1,
              tasks: {task.id: updatedTask},
              totalSize: task.uploadItem!.size,
              totalUploaded: task.uploadItem!.size,
              hasUploadInProgress: false,
            ),
            totalProgress: 1,
            controller: uploadController,
            equatableBust: UniqueKey(),
            uploadMethod: _uploadMethod!,
          ),
        );

        final undername = _getSelectedUndername()!;

        final newUndername = ARNSUndername(
          name: undername.name,
          domain: undername.domain,
          record: ARNSRecord(
            transactionId: metadata.dataTxId!,
            ttlSeconds: 3600,
          ),
        );

        await _arnsRepository.setUndernamesToFile(
          undername: newUndername,
          driveId: _targetDrive.id,
          fileId: metadata.id,
          processId: _selectedAntRecord!.processId,
          uploadNewRevision: false,
        );
      }
    }
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

  ARNSUndername? _getSelectedUndername() {
    if (_selectedUndername != null) {
      return _selectedUndername;
    }

    if (_selectedAntRecord != null) {
      return ARNSUndername(
        name: '@',
        domain: _selectedAntRecord!.domain,
        record: const ARNSRecord(
          transactionId: 'to_assign',
          ttlSeconds: 3600,
        ),
      );
    }

    return null;
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

    emit(UploadFailure(error: UploadErrors.unknown));
  }
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
