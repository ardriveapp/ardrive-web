import 'dart:async';

import 'package:ardrive/manifest/domain/exceptions.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
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

  /// The folder the picker opens in: the one the user was viewing, if any.
  final FolderID? _initialFolderId;

  final ManifestRepository _manifestRepository;
  final FolderRepository _folderRepository;

  bool _hasPendingFiles = false;

  StreamSubscription? _selectedFolderSubscription;

  final ArDriveAuth _auth;

  CreateManifestCubit({
    required ProfileCubit profileCubit,
    required Drive drive,
    FolderID? initialFolderId,
    required ManifestRepository manifestRepository,
    required FolderRepository folderRepository,
    required ArDriveAuth auth,
    bool hasPendingFiles = false,
  })  : _drive = drive,
        _initialFolderId = initialFolderId,
        _profileCubit = profileCubit,
        _hasPendingFiles = hasPendingFiles,
        _manifestRepository = manifestRepository,
        _folderRepository = folderRepository,
        _auth = auth,
        super(CreateManifestInitial()) {
    logger.i('Initializing CreateManifestCubit for drive: ${_drive.id}');
    if (_drive.isPrivate) {
      logger.i('Preventing manifest creation for private drive: ${_drive.id}');
      // Extra guardrail to prevent private drives from creating manifests
      // Private manifests need more consideration and are currently unavailable
      emit(CreateManifestPrivacyMismatch());
    }
    // Initialize folder selection immediately in the new workflow
    _initFolderSelection();
  }

  /// Initialize folder selection on creation
  Future<void> _initFolderSelection() async {
    try {
      await _loadInitialFolder();
    } catch (e) {
      // Or the dialog waits on "Loading folders" with nothing to press.
      addError(e);
    }
  }

  Future<void> _loadInitialFolder() async {
    logger.i('Initializing folder selection for drive: ${_drive.id}');
    rootFolderNode =
        await _folderRepository.getFolderNode(_drive.id, _drive.rootFolderId);
    logger.d('Root folder node loaded with id: ${rootFolderNode.folder.id}');

    _hasPendingFiles = await _hasPendingFilesInFolder(rootFolderNode);
    logger.d('Folder has pending files: $_hasPendingFiles');

    final initialFolderId = _initialFolderId;
    await loadFolder(
      initialFolderId != null &&
              _isShownInPicker(rootFolderNode, initialFolderId)
          ? initialFolderId
          : _drive.rootFolderId,
    );
  }

  /// Whether [folderId] is [node] or sits under it through folders the picker
  /// shows. The picker leaves out hidden folders, so it never opens in one or
  /// below one.
  bool _isShownInPicker(FolderNode node, FolderID folderId) {
    if (node.folder.id == folderId) {
      return true;
    }
    return node.subfolders.any(
      (subfolder) =>
          !subfolder.folder.isHidden && _isShownInPicker(subfolder, folderId),
    );
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
          freeStatus: info.freeStatus,
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
  ) =>
      _once(() => _confirmRevision(name));

  Future<void> _confirmRevision(String name) async {
    logger.i('Confirming manifest revision for name: $name');
    // A deployment is never named nothing.
    if (name.trim().isEmpty || state is! CreateManifestRevisionConfirm) return;
    final revisionConfirmationState = state as CreateManifestRevisionConfirm;
    final parentFolder = revisionConfirmationState.parentFolder;
    final existingManifestFileId =
        revisionConfirmationState.existingManifestFileId;

    emit(CreateManifestPreparingManifest(parentFolder: parentFolder));
    await prepareManifestTx(
        existingManifestFileId: existingManifestFileId, manifestName: name);
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

  /// The folder last asked for. Its contents arrive later, and until they
  /// do the screen still shows the one before.
  FolderID? _requestedFolderId;

  /// Whether the folder asked for is not the one [shown] holds yet.
  bool isLoadingFolder(CreateManifestFolderLoadSuccess shown) =>
      _requestedFolderId != null &&
      _requestedFolderId != shown.viewingFolder.folder.id;

  Future<void> loadFolder(String folderId) async {
    logger.i('Loading folder contents for folder: $folderId');
    _requestedFolderId = folderId;
    await _selectedFolderSubscription?.cancel();

    _selectedFolderSubscription = _folderRepository
        .watchFolderContents(driveId: _drive.id, folderId: folderId)
        .listen(
      (f) {
        // Two quick clicks can leave the first folder's stream running
        // past the second: only the folder asked for last is shown.
        if (folderId != _requestedFolderId) return;
        emit(
          CreateManifestFolderLoadSuccess(
            viewingRootFolder: f.folder.parentFolderId == null,
            viewingFolder: f,
            enableManifestCreationButton: _getEnableManifestCreationButton(),
          ),
        );
      },
      onError: (Object e, StackTrace s) => addError(e, s),
    );
  }

  /// User selected a new name due to name conflict, confirm that form is valid and check for conflicts again
  Future<void> reCheckConflicts(String name) =>
      _once(() => _reCheckConflicts(name));

  Future<void> _reCheckConflicts(String name) async {
    if (name.trim().isEmpty || state is! CreateManifestNameConflict) return;
    final conflictState = (state as CreateManifestNameConflict);
    final parentFolder = conflictState.parentFolder;
    final conflictingName = conflictState.conflictingName;

    if (name == conflictingName) {
      return;
    }

    emit(CreateManifestCheckingForConflicts(parentFolder: parentFolder));
    await checkNameConflicts(name);
  }

  Future<void> checkForConflicts(String name) =>
      _once(() => _checkForConflicts(name));

  Future<void> _checkForConflicts(String name) async {
    logger.i('Checking for manifest name conflicts: $name');
    if (name.trim().isEmpty) return;
    _reviewToRetry = null;

    /// Prevent multiple checks from being triggered
    final shown = state;
    // Not the folder on screen: the one asked for has not arrived.
    if (shown is CreateManifestFolderLoadSuccess && isLoadingFolder(shown)) {
      return;
    }
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

    logger.i('Performing name conflict check for: $name');

    await _selectedFolderSubscription?.cancel();

    final (bool, String?) conflictTuple;
    try {
      conflictTuple =
          await _manifestRepository.checkNameConflictAndReturnExistingFileId(
        driveId: _drive.id,
        parentFolderId: parentFolder.id,
        name: name,
      );
    } catch (e) {
      // The dialog shows "Preparing" with nothing to press until a state
      // replaces it.
      addError(e);
      return;
    }

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

    emit(CreateManifestPreparingManifest(
      parentFolder: parentFolder,
    ));
    await prepareManifestTx(manifestName: name);
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

      emit(
        CreateManifestUploadReview(
          manifestSize: await manifestFile.length,
          manifestName: manifestName,
          folderHasPendingFiles: _hasPendingFiles,
          manifestFile: manifestFile,
          drive: _drive,
          parentFolder: parentFolder,
          existingManifestFileId: existingManifestFileId,
          fallbackTxId: _getFallbackTxId(),
        ),
      );
    } catch (e) {
      logger.e('Failed to prepare manifest file', e);
      addError(e);
    }
  }

  /// Whether a step that writes or pays is running. Set before the first
  /// await: the dialog's button stays enabled until the cubit emits its busy
  /// state, and a fast second press would otherwise start a second step.
  bool _inFlight = false;

  Future<void> _once(Future<void> Function() step) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await step();
    } finally {
      _inFlight = false;
    }
  }

  /// The review the last upload started from, for [retryUpload].
  CreateManifestUploadReview? _reviewToRetry;

  /// After a failed upload: the same deployment again, from the review it
  /// was started from. Nothing else changes, so what was chosen there, the
  /// payment method included, is what is sent.
  Future<void> retryUpload() async {
    await _once(() async {
      final review = _reviewToRetry;
      final failure = state;
      // Only where nothing was posted: after a post, a second upload pays
      // twice.
      if (review == null ||
          failure is! CreateManifestFailure ||
          !failure.canRetry) {
        return;
      }

      emit(review);
      await _uploadManifest();
    });
  }

  Future<void> uploadManifest({UploadMethod? method}) =>
      _once(() => _uploadManifest(method: method));

  Future<void> _uploadManifest({UploadMethod? method}) async {
    logger.i('Starting manifest upload process');
    // What was approved is what is sent: the wallet check can take a while,
    // and the review may change under it.
    final approved = state;
    try {
      if (await _profileCubit.logoutIfWalletMismatch()) {
        logger.i('Wallet mismatch detected, canceling upload');
        emit(CreateManifestWalletMismatch());
        return;
      }
    } on ArConnectUnavailableException catch (e) {
      // Wander couldn't be reached and the person chose Cancel. Nothing was
      // sent: the review stays, to try again or close.
      logger.w('Could not check the wallet before a manifest upload: $e');
      return;
    }

    if (approved is CreateManifestUploadReview) {
      try {
        final createManifestUploadReview = approved;
        // With the method it is sent by, so Try again pays the same way.
        _reviewToRetry = createManifestUploadReview.copyWith(
          uploadMethod: method ?? createManifestUploadReview.uploadMethod,
        );
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

        final dataTxId = await _manifestRepository.uploadManifest(
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
          onProgress: (progress) => emit(
            CreateManifestUploadInProgress(
              progress: progress,
            ),
          ),
        );

        emit(CreateManifestSuccess(
          parentFolder: createManifestUploadReview.parentFolder,
          dataTxId: dataTxId,
          name: createManifestUploadReview.manifestName,
        ));
      } catch (e) {
        logger.e('An error occured uploading the manifest.', e);
        addError(e);
      }
    }
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
    final wrapped = error is ManifestCreationException ? error.error : error;
    // Emitting after close throws, and that throw comes back here.
    if (!isClosed) {
      emit(CreateManifestFailure(
        isPaymentError: isTurboPaymentError(wrapped),
        postedTxId: error is ManifestPostedException ? error.dataTxId : null,
        canRetry: _reviewToRetry != null &&
            error is! ManifestPostedException &&
            _failedBeforeSubmission(error),
        maybeSent: error is! ManifestPostedException &&
            !_failedBeforeSubmission(error),
      ));
    }
    super.onError(error, stackTrace);
  }
}

/// Whether a failed upload is known to have sent nothing, so that a fresh
/// try cannot pay twice. Failures that are not about a task, such as a
/// manifest that could not be built, sent nothing.
bool _failedBeforeSubmission(Object error) {
  Object? inner = error is ManifestCreationException ? error.error : error;
  if (inner is UnderFundException) inner = inner.error;
  if (inner is! List) return true;
  for (final task in inner) {
    if (task is! FileUploadTask) continue;
    // Turbo took the metadata item: the deployment is on its way, and what
    // is left is the data item, which a new upload would pay for again.
    if (task.metadataUploaded) return false;
    // Direct to the network: once the transaction is built and signed, a
    // failure may have reached the network. The uploader says as much of a
    // failed header post, which a gateway can store and still answer with
    // an error. Only a cancel, or a failure before there was a transaction,
    // sent nothing.
    if (task.type == UploadType.d2n &&
        task.uploadItem != null &&
        task.error is! UploadCanceledException) {
      return false;
    }
  }
  return true;
}

class UploadManifestParams {
  final Transaction signedBundleTx;
  final Future<void> Function() addManifestToDatabase;

  UploadManifestParams({
    required this.signedBundleTx,
    required this.addManifestToDatabase,
  });
}
