import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/manifest_data.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pst/pst.dart';
import 'package:uuid/uuid.dart';

import '../../core/upload/cost_calculator.dart';

part 'create_manifest_state.dart';

class CreateManifestCubit extends Cubit<CreateManifestState> {
  late FolderNode rootFolderNode;

  final ProfileCubit _profileCubit;
  final Drive drive;

  final ArweaveService _arweave;
  final TurboUploadService _turboUploadService;
  final DriveDao _driveDao;
  final PstService _pst;
  bool _hasPendingFiles = false;

  StreamSubscription? _selectedFolderSubscription;

  CreateManifestCubit({
    required this.drive,
    required ProfileCubit profileCubit,
    required ArweaveService arweave,
    required TurboUploadService turboUploadService,
    required DriveDao driveDao,
    required PstService pst,
    required bool hasPendingFiles,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _turboUploadService = turboUploadService,
        _driveDao = driveDao,
        _pst = pst,
        _hasPendingFiles = hasPendingFiles,
        super(CreateManifestInitial()) {
    if (drive.isPrivate) {
      // Extra guardrail to prevent private drives from creating manifests
      // Private manifests need more consideration and are currently unavailable
      emit(CreateManifestPrivacyMismatch());
    }
  }

  /// Validate form before User begins choosing a target folder
  Future<void> chooseTargetFolder() async {
    rootFolderNode =
        await _driveDao.getFolderTree(drive.id, drive.rootFolderId);

    _hasPendingFiles = await _hasPendingFilesInFolder(rootFolderNode);

    await loadFolder(drive.rootFolderId);
  }

  /// User has confirmed that they would like to submit a manifest revision transaction
  Future<void> confirmRevision(
    String name,
  ) async {
    final revisionConfirmationState = state as CreateManifestRevisionConfirm;
    final parentFolder = revisionConfirmationState.parentFolder;
    final existingManifestFileId =
        revisionConfirmationState.existingManifestFileId;

    emit(CreateManifestPreparingManifest(parentFolder: parentFolder));
    await prepareManifestTx(
        existingManifestFileId: existingManifestFileId, manifestName: name);
  }

  Future<void> loadParentFolder() async {
    final state = this.state as CreateManifestFolderLoadSuccess;
    if (state.viewingFolder.folder.parentFolderId != null) {
      return loadFolder(state.viewingFolder.folder.parentFolderId!);
    }
  }

  /// recursively check if any files in the folder have pending uploads
  Future<bool> _hasPendingFilesInFolder(FolderNode folder) async {
    final files = folder.getRecursiveFiles();
    final folders = folder.subfolders;

    if (files.isEmpty && folders.isEmpty) {
      return false;
    }

    final filesWithTx = await _driveDao
        .filesInFolderWithRevisionTransactions(
            driveId: drive.id, parentFolderId: folder.folder.id)
        .get();

    final hasPendingFiles = filesWithTx.any((e) =>
        'pending' ==
        fileStatusFromTransactions(
          e.metadataTx,
          e.dataTx,
        ).toString());

    if (hasPendingFiles) {
      return true;
    }

    for (var folder in folders) {
      if (await _hasPendingFilesInFolder(folder)) {
        return true;
      }
    }

    return false;
  }

  Future<void> loadFolder(String folderId) async {
    await _selectedFolderSubscription?.cancel();

    _selectedFolderSubscription = _driveDao
        .watchFolderContents(
          drive.id,
          folderId: folderId,
        )
        .listen(
          (f) => emit(
            CreateManifestFolderLoadSuccess(
              viewingRootFolder: f.folder.parentFolderId == null,
              viewingFolder: f,
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
    final parentFolder =
        (state as CreateManifestFolderLoadSuccess).viewingFolder.folder;

    emit(CreateManifestCheckingForConflicts(parentFolder: parentFolder));
    await checkNameConflicts(name);
  }

  Future<void> checkNameConflicts(String name) async {
    final parentFolder =
        (state as CreateManifestCheckingForConflicts).parentFolder;
    await _selectedFolderSubscription?.cancel();

    final foldersWithName = await _driveDao
        .foldersInFolderWithName(
            driveId: drive.id, parentFolderId: parentFolder.id, name: name)
        .get();
    final filesWithName = await _driveDao
        .filesInFolderWithName(
            driveId: drive.id, parentFolderId: parentFolder.id, name: name)
        .get();

    final conflictingFiles =
        filesWithName.where((e) => e.dataContentType != ContentType.manifest);

    if (foldersWithName.isNotEmpty || conflictingFiles.isNotEmpty) {
      // Name conflicts with existing file or folder
      // This is an error case, send user back to naming the manifest
      emit(
        CreateManifestNameConflict(
          conflictingName: name,
          parentFolder: parentFolder,
        ),
      );
      return;
    }

    final manifestRevisionId = filesWithName
        .firstWhereOrNull((e) => e.dataContentType == ContentType.manifest)
        ?.id;

    if (manifestRevisionId != null) {
      emit(
        CreateManifestRevisionConfirm(
          existingManifestFileId: manifestRevisionId,
          parentFolder: parentFolder,
        ),
      );
      return;
    }
    emit(CreateManifestPreparingManifest(parentFolder: parentFolder));
    await prepareManifestTx(manifestName: name);
  }

  Future<void> prepareManifestTx({
    FileID? existingManifestFileId,
    required String manifestName,
  }) async {
    try {
      final parentFolder =
          (state as CreateManifestPreparingManifest).parentFolder;
      final folderNode = rootFolderNode.searchForFolder(parentFolder.id) ??
          await _driveDao.getFolderTree(drive.id, parentFolder.id);
      final arweaveManifest = ManifestData.fromFolderNode(
        folderNode: folderNode,
      );

      final profile = _profileCubit.state as ProfileLoggedIn;
      final wallet = profile.wallet;

      final manifestDataItem = await arweaveManifest.asPreparedDataItem(
        owner: await wallet.getOwner(),
      );
      await manifestDataItem.sign(wallet);

      /// Assemble data JSON of the metadata tx for the manifest
      final manifestFileEntity = FileEntity(
        size: arweaveManifest.size,
        parentFolderId: parentFolder.id,
        name: manifestName,
        lastModifiedDate: DateTime.now(),
        id: existingManifestFileId ?? const Uuid().v4(),
        driveId: drive.id,
        dataTxId: manifestDataItem.id,
        dataContentType: ContentType.manifest,
      );

      final manifestMetaDataItem = await _arweave.prepareEntityDataItem(
        manifestFileEntity,
        wallet,
      );

      // Sign data item and preserve meta data tx ID on entity
      await manifestMetaDataItem.sign(wallet);
      manifestFileEntity.txId = manifestMetaDataItem.id;

      addManifestToDatabase() => _driveDao.transaction(
            () async {
              await _driveDao.writeFileEntity(
                manifestFileEntity,
                '${parentFolder.path}/$manifestName',
              );
              await _driveDao.insertFileRevision(
                manifestFileEntity.toRevisionCompanion(
                  performedAction: existingManifestFileId == null
                      ? RevisionAction.create
                      : RevisionAction.uploadNewVersion,
                ),
              );
            },
          );

      logger.d('Manifest has pending files: $_hasPendingFiles');

      final canUseTurbo = _turboUploadService.useTurboUpload &&
          arweaveManifest.size < _turboUploadService.allowedDataItemSize;
      if (canUseTurbo) {
        emit(
          CreateManifestTurboUploadConfirmation(
            manifestSize: arweaveManifest.size,
            manifestName: manifestName,
            folderHasPendingFiles: _hasPendingFiles,
            manifestDataItems: [manifestDataItem, manifestMetaDataItem],
            addManifestToDatabase: addManifestToDatabase,
          ),
        );
        return;
      }

      final bundle = await DataBundle.fromDataItems(
        items: [manifestDataItem, manifestMetaDataItem],
      );

      final bundleTx = await _arweave.prepareDataBundleTxFromBlob(
        bundle.blob,
        wallet,
      );
      await _pst.addCommunityTipToTx(bundleTx);

      final totalCost = bundleTx.reward + bundleTx.quantity;

      if (profile.walletBalance < totalCost) {
        emit(
          CreateManifestInsufficientBalance(
            walletBalance: winstonToAr(profile.walletBalance),
            totalCost: winstonToAr(totalCost),
          ),
        );
        return;
      }

      final arUploadCost = winstonToAr(totalCost);

      final double? usdUploadCost = await ConvertArToUSD(arweave: _arweave)
          .convertForUSD(double.parse(arUploadCost));

      // Sign bundle tx and preserve bundle tx ID on entity
      await bundleTx.sign(wallet);
      manifestFileEntity.bundledIn = bundleTx.id;

      final uploadManifestParams = UploadManifestParams(
        signedBundleTx: bundleTx,
        addManifestToDatabase: addManifestToDatabase,
      );

      emit(
        CreateManifestUploadConfirmation(
          manifestSize: arweaveManifest.size,
          manifestName: manifestName,
          folderHasPendingFiles: _hasPendingFiles,
          arUploadCost: arUploadCost,
          usdUploadCost: usdUploadCost,
          uploadManifestParams: uploadManifestParams,
        ),
      );
    } catch (err) {
      addError(err);
    }
  }

  Future<void> uploadManifest() async {
    if (await _profileCubit.logoutIfWalletMismatch()) {
      emit(CreateManifestWalletMismatch());
      return;
    }
    if (state is CreateManifestTurboUploadConfirmation) {
      final params = state as CreateManifestTurboUploadConfirmation;
      emit(CreateManifestUploadInProgress());
      try {
        for (var dataItem in params.manifestDataItems) {
          await _turboUploadService.postDataItem(
            dataItem: dataItem,
            wallet: (_profileCubit.state as ProfileLoggedIn).wallet,
          );
        }

        await params.addManifestToDatabase();

        emit(CreateManifestSuccess());
      } catch (err) {
        addError(err);
      }
      return;
    }
    final params =
        (state as CreateManifestUploadConfirmation).uploadManifestParams;

    emit(CreateManifestUploadInProgress());
    try {
      await _arweave.client.transactions
          .upload(
            params.signedBundleTx,
            maxConcurrentUploadCount: maxConcurrentUploadCount,
          )
          .drain();
      await params.addManifestToDatabase();

      emit(CreateManifestSuccess());
    } catch (err) {
      addError(err);
    }
  }

  @override
  Future<void> close() async {
    await _selectedFolderSubscription?.cancel();
    await super.close();
  }

  void backToName() {
    emit(CreateManifestInitial());
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(CreateManifestFailure());
    super.onError(error, stackTrace);

    logger.e('Failed to create manifest', error, stackTrace);
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
