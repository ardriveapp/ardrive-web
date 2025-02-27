import 'dart:async';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/manifest/domain/manifest_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'create_manifest_state.dart';

// TODO: Add tests for CreateManifestCubit
class CreateManifestCubit extends Cubit<CreateManifestState> {
  late FolderNode rootFolderNode;

  final ProfileCubit _profileCubit;
  final Drive _drive;

  final ManifestRepository _manifestRepository;
  final FolderRepository _folderRepository;
  final ARNSRepository _arnsRepository;

  bool _hasPendingFiles = false;

  StreamSubscription? _selectedFolderSubscription;

  final ArDriveAuth _auth;

  ArNSNameModel? _selectedAntRecord;
  ARNSUndername? _selectedUndername;

  CreateManifestCubit({
    required ProfileCubit profileCubit,
    required Drive drive,
    required ManifestRepository manifestRepository,
    required FolderRepository folderRepository,
    required ArDriveAuth auth,
    bool hasPendingFiles = false,
    required ARNSRepository arnsRepository,
  })  : _drive = drive,
        _profileCubit = profileCubit,
        _hasPendingFiles = hasPendingFiles,
        _manifestRepository = manifestRepository,
        _folderRepository = folderRepository,
        _arnsRepository = arnsRepository,
        _auth = auth,
        super(CreateManifestInitial()) {
    logger.i('Initializing CreateManifestCubit for drive: ${_drive.id}');
    if (_drive.isPrivate) {
      logger.i('Preventing manifest creation for private drive: ${_drive.id}');
      // Extra guardrail to prevent private drives from creating manifests
      // Private manifests need more consideration and are currently unavailable
      emit(CreateManifestPrivacyMismatch());
    }
  }

  void selectUploadMethod(
      UploadMethod method, UploadPaymentMethodInfo info, bool canUpload) {
    logger.d(
        'Selecting upload method: $method, canUpload: $canUpload, isFreeUpload: ${info.isFreeThanksToTurbo}');
    if (state is CreateManifestUploadReview) {
      emit(
        (state as CreateManifestUploadReview).copyWith(
          uploadMethod: method,
          canUpload: canUpload,
          freeUpload: info.isFreeThanksToTurbo,
          assignedName: (state as CreateManifestUploadReview).assignedName,
          fallbackTxId: (state as CreateManifestUploadReview).fallbackTxId,
        ),
      );
    }
  }

  /// Validate form before User begins choosing a target folder
  Future<void> chooseTargetFolder() async {
    logger.i('Choosing target folder for drive: ${_drive.id}');
    rootFolderNode =
        await _folderRepository.getFolderNode(_drive.id, _drive.rootFolderId);
    logger.d('Root folder node loaded with id: ${rootFolderNode.folder.id}');

    _hasPendingFiles = await _hasPendingFilesInFolder(rootFolderNode);
    logger.d('Folder has pending files: $_hasPendingFiles');

    await loadFolder(_drive.rootFolderId);
  }

  /// User has confirmed that they would like to submit a manifest revision transaction
  Future<void> confirmRevision(
    String name,
  ) async {
    logger.i('Confirming manifest revision for name: $name');
    final revisionConfirmationState = state as CreateManifestRevisionConfirm;

    final arns = await _arnsRepository
        .getAntRecordsForWallet(_auth.currentUser.walletAddress);
    logger.d(
        'Found ${arns.length} ANT records for wallet: ${_auth.currentUser.walletAddress}');

    if (arns.isNotEmpty) {
      emit(
        CreateManifestPreparingManifestWithARNS(
          parentFolder: revisionConfirmationState.parentFolder,
          manifestName: name,
          existingManifestFileId:
              revisionConfirmationState.existingManifestFileId,
        ),
      );
    } else {
      final parentFolder = revisionConfirmationState.parentFolder;
      final existingManifestFileId =
          revisionConfirmationState.existingManifestFileId;

      emit(CreateManifestPreparingManifest(parentFolder: parentFolder));
      await prepareManifestTx(
          existingManifestFileId: existingManifestFileId, manifestName: name);
    }
  }

  Future<void> loadParentFolder() async {
    logger.d('Loading parent folder');
    final state = this.state as CreateManifestFolderLoadSuccess;
    if (state.viewingFolder.folder.parentFolderId != null) {
      logger.d(
          'Loading parent folder with id: ${state.viewingFolder.folder.parentFolderId}');
      return loadFolder(state.viewingFolder.folder.parentFolderId!);
    }
  }

  /// recursively check if any files in the folder have pending uploads
  Future<bool> _hasPendingFilesInFolder(FolderNode folder) async {
    return _manifestRepository.hasPendingFilesOnTargetFolder(
      folderNode: folder,
    );
  }

  Future<void> loadFolder(String folderId) async {
    logger.i('Loading folder contents for folder: $folderId');
    await _selectedFolderSubscription?.cancel();

    _selectedFolderSubscription = _folderRepository
        .watchFolderContents(driveId: _drive.id, folderId: folderId)
        .listen(
          (f) => emit(
            CreateManifestFolderLoadSuccess(
              viewingRootFolder: f.folder.parentFolderId == null,
              viewingFolder: f,
              enableManifestCreationButton: _getEnableManifestCreationButton(),
            ),
          ),
        );
  }

  /// User selected a new name due to name conflict, confirm that form is valid and check for conflicts again
  Future<void> reCheckConflicts(String name) async {
    final conflictState = (state as CreateManifestNameConflict);
    final parentFolder = conflictState.parentFolder;
    final conflictingName = conflictState.conflictingName;

    if (name == conflictingName) {
      return;
    }

    emit(CreateManifestCheckingForConflicts(parentFolder: parentFolder));
    await checkNameConflicts(name);
  }

  Future<void> checkForConflicts(String name) async {
    logger.i('Checking for manifest name conflicts: $name');

    /// Prevent multiple checks from being triggered
    if (state is! CreateManifestFolderLoadSuccess) {
      logger.d('Skipping conflict check - invalid state: $state');
      return;
    }

    final parentFolder =
        (state as CreateManifestFolderLoadSuccess).viewingFolder.folder;

    emit(CreateManifestCheckingForConflicts(parentFolder: parentFolder));
    await checkNameConflicts(name);
  }

  Future<void> checkNameConflicts(String name) async {
    final parentFolder =
        (state as CreateManifestCheckingForConflicts).parentFolder;

    emit(CreateManifestLoadingARNS(
      parentFolder: parentFolder,
      manifestName: name,
    ));

    logger.i('Performing name conflict check for: $name');
    final arns = await _getAntRecordsForWallet();
    logger.d('Found ${arns.length} ANT records for current wallet');

    await _selectedFolderSubscription?.cancel();

    final conflictTuple =
        await _manifestRepository.checkNameConflictAndReturnExistingFileId(
      driveId: _drive.id,
      parentFolderId: parentFolder.id,
      name: name,
    );

    final hasConflictNames = conflictTuple.$1;
    final existingManifestFileId = conflictTuple.$2;

    if (hasConflictNames) {
      emit(CreateManifestNameConflict(
        conflictingName: name,
        parentFolder: parentFolder,
      ));
      return;
    }

    final manifestRevisionId = existingManifestFileId;

    if (manifestRevisionId != null) {
      emit(
        CreateManifestRevisionConfirm(
          existingManifestFileId: manifestRevisionId,
          parentFolder: parentFolder,
        ),
      );
      return;
    }

    if (arns.isNotEmpty) {
      emit(CreateManifestPreparingManifestWithARNS(
          parentFolder: parentFolder, manifestName: name));
    } else {
      emit(CreateManifestPreparingManifest(
        parentFolder: parentFolder,
      ));
      await prepareManifestTx(manifestName: name);
    }
  }

  /// Fetches ANT records for the current wallet, returns an empty list if the operation fails
  Future<List<ANTRecord>> _getAntRecordsForWallet() async {
    try {
      return await _arnsRepository
          .getAntRecordsForWallet(_auth.currentUser.walletAddress)
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      logger.e('Failed to load ANT records. Proceeding with empty list', e);
      return [];
    }
  }

  Future<void> prepareManifestTx({
    FileID? existingManifestFileId,
    required String manifestName,
    String? folderId,
  }) async {
    logger.i('Preparing manifest transaction for name: $manifestName');
    logger.d(
        'Existing manifest file ID: $existingManifestFileId, Target folder ID: $folderId');
    FolderEntry parentFolder;
    if (folderId != null) {
      rootFolderNode =
          await _folderRepository.getFolderNode(_drive.id, folderId);
      parentFolder = rootFolderNode.folder;
    } else {
      switch (state) {
        case CreateManifestPreparingManifestWithARNS s:
          parentFolder = s.parentFolder;
          existingManifestFileId = s.existingManifestFileId;
        case CreateManifestPreparingManifest s:
          parentFolder = s.parentFolder;
        default:
          throw StateError('Unexpected state: $state');
      }
    }

    try {
      final manifestFile = await _manifestRepository.getManifestFile(
        parentFolder: parentFolder,
        manifestName: manifestName,
        rootFolderNode: rootFolderNode,
        driveId: _drive.id,
        fallbackTxId: _getFallbackTxId(),
      );

      ARNSUndername? undername = getSelectedUndername();

      emit(
        CreateManifestUploadReview(
          manifestSize: await manifestFile.length,
          manifestName: manifestName,
          folderHasPendingFiles: _hasPendingFiles,
          manifestFile: manifestFile,
          drive: _drive,
          parentFolder: parentFolder,
          existingManifestFileId: existingManifestFileId,
          assignedName:
              undername != null ? getLiteralARNSRecordName(undername) : null,
          fallbackTxId: _getFallbackTxId(),
        ),
      );
    } catch (e) {
      logger.e('Failed to prepare manifest file', e);
      addError(e);
    }
  }

  Future<void> uploadManifest({UploadMethod? method}) async {
    logger.i('Starting manifest upload process');
    if (await _profileCubit.logoutIfWalletMismatch()) {
      logger.i('Wallet mismatch detected, canceling upload');
      emit(CreateManifestWalletMismatch());
      return;
    }

    if (state is CreateManifestUploadReview) {
      try {
        final createManifestUploadReview = state as CreateManifestUploadReview;
        final uploadType =
            (method ?? createManifestUploadReview.uploadMethod) ==
                    UploadMethod.ar
                ? UploadType.d2n
                : UploadType.turbo;

        emit(CreateManifestUploadInProgress(
          progress: CreateManifestUploadProgress.preparingManifest,
        ));

        logger.d(
            'Uploading manifest file with existing manifest file id: ${createManifestUploadReview.existingManifestFileId}');

        await _manifestRepository.uploadManifest(
          params: ManifestUploadParams(
            manifestFile: createManifestUploadReview.manifestFile,
            driveId: _drive.id,
            parentFolderId: createManifestUploadReview.parentFolder.id,
            existingManifestFileId:
                createManifestUploadReview.existingManifestFileId,
            uploadType: uploadType,
            wallet: _auth.currentUser.wallet,
            fallbackTxId: _getFallbackTxId(),
          ),
          processId: _selectedAntRecord?.processId,
          undername: getSelectedUndername(),
          onProgress: (progress) => emit(
            CreateManifestUploadInProgress(
              progress: progress,
            ),
          ),
        );

        emit(CreateManifestSuccess(
          nameAssignedByArNS: _selectedUndername != null,
        ));
      } catch (e) {
        logger.e('An error occured uploading the manifest.', e);
        addError(e);
      }
    }
  }

  void openAssignNameModal() {
    logger.d('Opening assign name modal');
    emit(
      CreateManifestPreparingManifestWithARNS(
        parentFolder:
            (state as CreateManifestPreparingManifestWithARNS).parentFolder,
        manifestName:
            (state as CreateManifestPreparingManifestWithARNS).manifestName,
        existingManifestFileId:
            (state as CreateManifestPreparingManifestWithARNS)
                .existingManifestFileId,
        showAssignNameModal: true,
      ),
    );
  }

  ARNSUndername? getSelectedUndername() {
    if (_selectedUndername != null) {
      return _selectedUndername;
    }

    if (_selectedAntRecord != null) {
      return ARNSUndernameFactory.createDefaultUndername(
        domain: _selectedAntRecord!.name,
        transactionId: 'to_assign',
      );
    }

    return null;
  }

  void selectArns(ArNSNameModel? antRecord, ARNSUndername? undername) {
    logger.i(
        'Selecting ARNS: antRecord: ${antRecord?.name}, undername: ${undername?.name}');
    _selectedAntRecord = antRecord;
    _selectedUndername = undername;

    final manifestName =
        (state as CreateManifestPreparingManifestWithARNS).manifestName;

    prepareManifestTx(manifestName: manifestName);
  }

  TxID? _fallbackTxId;

  void setFallbackTxId(TxID txId, {bool emitState = true}) {
    logger.d('Setting fallback transaction ID: $txId');
    _fallbackTxId = txId;

    if (emitState) {
      emit(
        (state as CreateManifestFolderLoadSuccess).copyWith(
          fallbackTxId: _getFallbackTxId(),
          enableManifestCreationButton: _getEnableManifestCreationButton(),
        ),
      );
    }
  }

  TxID? _getFallbackTxId() {
    if (_fallbackTxId == null || _fallbackTxId!.isEmpty) {
      return null;
    }

    return _fallbackTxId;
  }

  bool _getEnableManifestCreationButton() {
    return _getFallbackTxId() == null ||
        _getFallbackTxId()!.isEmpty ||
        isValidArweaveTxId(_getFallbackTxId()!);
  }

  @override
  Future<void> close() async {
    await _selectedFolderSubscription?.cancel();
    await super.close();
  }

  void backToName() {
    logger.d('Navigating back to name input');
    emit(CreateManifestInitial());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    logger.e('Failed to create manifest', error, stackTrace);
    emit(CreateManifestFailure());
    super.onError(error, stackTrace);
  }
}

class UploadManifestParams {
  final Transaction signedBundleTx;
  final Future<void> Function() addManifestToDatabase;

  UploadManifestParams({
    required this.signedBundleTx,
    required this.addManifestToDatabase,
  });
}
