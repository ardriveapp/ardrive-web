import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';

import '../blocs.dart';

part 'sync_state.dart';

const kRequiredTxConfirmationCount = 15;

/// The [SyncCubit] periodically syncs the user's owned and attached drives and their contents.
/// It also checks the status of unconfirmed transactions made by revisions.
class SyncCubit extends Cubit<SyncState> {
  final ProfileCubit _profileCubit;
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final Database _db;

  StreamSubscription _syncSub;

  SyncCubit({
    @required ProfileCubit profileCubit,
    @required ArweaveService arweave,
    @required DriveDao driveDao,
    @required Database db,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _db = db,
        super(SyncIdle()) {
    // Sync the user's drives on start and periodically.
    _syncSub = interval(const Duration(minutes: 2))
        .startWith(null)
        // Do not start another sync until the previous sync has completed.
        .exhaustMap((value) => Stream.fromFuture(startSync()))
        .listen((_) {});
  }

  Future<void> startSync() async {
    emit(SyncInProgress());

    try {
      final profile = _profileCubit.state;

      // Only sync in drives owned by the user if they're logged in.
      if (profile is ProfileLoggedIn) {
        final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
            profile.wallet, profile.password);

        await _driveDao.updateUserDrives(userDriveEntities, profile.cipherKey);
      }

      // Sync the contents of each drive attached in the app.
      final driveIds = await _driveDao.allDrives().map((d) => d.id).get();
      final driveSyncProcesses = driveIds.map((driveId) => _syncDrive(driveId));
      await Future.wait(driveSyncProcesses);

      await _updateTransactionStatuses();
    } catch (err) {
      addError(err);
    }

    emit(SyncIdle());
  }

  Future<void> _syncDrive(String driveId) async {
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();

    SecretKey driveKey;
    if (drive.isPrivate) {
      final profile = _profileCubit.state;

      // Only sync private drives when the user is logged in.
      if (profile is ProfileLoggedIn) {
        driveKey = await _driveDao.getDriveKey(drive.id, profile.cipherKey);
      } else {
        return;
      }
    }

    final entityHistory = await _arweave.getNewEntitiesForDrive(
      drive.id,
      // We should start syncing from the block after the latest one we already synced from.
      after: drive.syncCursor,
      driveKey: driveKey,
    );

    // Create entries for all the new revisions of file and folders in this drive.
    final newEntities = entityHistory.blockHistory
        .map((b) => b.entities)
        .expand((entities) => entities);

    await _db.transaction(() async {
      final folderRevisions = await _addNewFolderEntityRevisions(
          driveId, newEntities.whereType<FolderEntity>());
      final fileRevisions = await _addNewFileEntityRevisions(
          driveId, newEntities.whereType<FileEntity>());

      final updatedFoldersById =
          await _computeRefreshedFolderEntriesFromRevisions(
              driveId, folderRevisions);
      final updatedFilesById = await _computeRefreshedFileEntriesFromRevisions(
          driveId, fileRevisions);

      // Update the folder and file entries before generating their new paths.
      await _db.batch((b) {
        b.insertAllOnConflictUpdate(
            _db.folderEntries, updatedFoldersById.values.toList());
        b.insertAllOnConflictUpdate(
            _db.fileEntries, updatedFilesById.values.toList());
      });

      await generateFsEntryPaths(driveId, updatedFoldersById, updatedFilesById);

      await _driveDao.writeToDrive(DrivesCompanion(
          id: Value(drive.id), syncCursor: Value(entityHistory.cursor)));
    });
  }

  /// Computes the new folder revisions from the provided entities, inserts them into the database
  /// , and returns only the latest revisions.
  Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions(
      String driveId, Iterable<FolderEntity> newEntities) async {
    // The latest folder revisions, keyed by their entity ids.
    final latestRevisions = <String, FolderRevisionsCompanion>{};

    final newRevisions = <FolderRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        latestRevisions[entity.id] = await _driveDao
            .latestFolderRevisionByFolderId(
                driveId: driveId, folderId: entity.id)
            .getSingleOrNull()
            .then((r) => r?.toCompanion(true));
      }

      final revisionPerformedAction =
          entity.getPerformedRevisionAction(latestRevisions[entity.id]);
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value == null) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id] = revision;
    }

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.folderRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .map(
                (rev) => NetworkTransactionsCompanion.insert(
                  id: rev.metadataTxId.value,
                  status: Value(TransactionStatus.confirmed),
                ),
              )
              .toList());
    });

    return latestRevisions.values.toList();
  }

  /// Computes the new file revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions(
      String driveId, Iterable<FileEntity> newEntities) async {
    // The latest file revisions, keyed by their entity ids.
    final latestRevisions = <String, FileRevisionsCompanion>{};

    final newRevisions = <FileRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        latestRevisions[entity.id] = await _driveDao
            .latestFileRevisionByFileId(driveId: driveId, fileId: entity.id)
            .getSingleOrNull()
            .then((r) => r?.toCompanion(true));
      }

      final revisionPerformedAction =
          entity.getPerformedRevisionAction(latestRevisions[entity.id]);
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value == null) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id] = revision;
    }

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.fileRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .expand(
                (rev) => [
                  NetworkTransactionsCompanion.insert(
                    id: rev.metadataTxId.value,
                    status: Value(TransactionStatus.confirmed),
                  ),
                  // We cannot be sure that the data tx of files have been mined
                  // so we'll mark it as pending initially.
                  NetworkTransactionsCompanion.insert(
                    id: rev.dataTxId.value,
                    status: Value(TransactionStatus.pending),
                  ),
                ],
              )
              .toList());
    });

    return latestRevisions.values.toList();
  }

  /// Computes the refreshed folder entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FolderEntriesCompanion>>
      _computeRefreshedFolderEntriesFromRevisions(String driveId,
          List<FolderRevisionsCompanion> revisionsByFolderId) async {
    final updatedFoldersById = {
      for (final revision in revisionsByFolderId)
        revision.folderId.value: revision.toEntryCompanion(),
    };

    for (final folderId in updatedFoldersById.keys) {
      final oldestRevision = await _driveDao
          .oldestFolderRevisionByFolderId(driveId: driveId, folderId: folderId)
          .getSingleOrNull();

      updatedFoldersById[folderId] = updatedFoldersById[folderId].copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFoldersById[folderId].dateCreated));
    }

    return updatedFoldersById;
  }

  /// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FileEntriesCompanion>>
      _computeRefreshedFileEntriesFromRevisions(String driveId,
          List<FileRevisionsCompanion> revisionsByFileId) async {
    final updatedFilesById = {
      for (final revision in revisionsByFileId)
        revision.fileId.value: revision.toEntryCompanion(),
    };

    for (final fileId in updatedFilesById.keys) {
      final oldestRevision = await _driveDao
          .oldestFileRevisionByFileId(driveId: driveId, fileId: fileId)
          .getSingleOrNull();

      updatedFilesById[fileId] = updatedFilesById[fileId].copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFilesById[fileId].dateCreated));
    }

    return updatedFilesById;
  }

  /// Generates paths for the folders (and their subchildren) and files provided.
  Future<void> generateFsEntryPaths(
    String driveId,
    Map<String, FolderEntriesCompanion> foldersByIdMap,
    Map<String, FileEntriesCompanion> filesByIdMap,
  ) async {
    final staleFolderTree = <FolderNode>[];
    for (final folder in foldersByIdMap.values) {
      // Get trees of the updated folders and files for path generation.
      final tree = await _driveDao.getFolderTree(driveId, folder.id.value);

      // Remove any trees that are a subset of another.
      var newTreeIsSubsetOfExisting = false;
      var newTreeIsSupersetOfExisting = false;
      for (final existingTree in staleFolderTree) {
        if (existingTree.searchForFolder(tree.folder.id) != null) {
          newTreeIsSubsetOfExisting = true;
        } else if (tree.searchForFolder(existingTree.folder.id) != null) {
          staleFolderTree.remove(existingTree);
          staleFolderTree.add(tree);
          newTreeIsSupersetOfExisting = true;
        }
      }

      if (!newTreeIsSubsetOfExisting && !newTreeIsSupersetOfExisting) {
        staleFolderTree.add(tree);
      }
    }

    Future<void> updateFolderTree(FolderNode node, String parentPath) async {
      final folderId = node.folder.id;
      // If this is the root folder, we should not include its name as part of the path.
      final folderPath = node.folder.parentFolderId != null
          ? parentPath + '/' + node.folder.name
          : '';

      await _driveDao
          .updateFolderById(driveId, folderId)
          .write(FolderEntriesCompanion(path: Value(folderPath)));

      for (final staleFileId in node.files.keys) {
        final filePath = folderPath + '/' + node.files[staleFileId];

        await _driveDao
            .updateFileById(driveId, staleFileId)
            .write(FileEntriesCompanion(path: Value(filePath)));
      }

      for (final staleFolder in node.subfolders) {
        await updateFolderTree(staleFolder, folderPath);
      }
    }

    for (final treeRoot in staleFolderTree) {
      // Get the path of this folder's parent.
      String parentPath;
      if (treeRoot.folder.parentFolderId == null) {
        parentPath = '';
      } else {
        parentPath = await _driveDao
            .folderById(
                driveId: driveId, folderId: treeRoot.folder.parentFolderId)
            .map((f) => f.path)
            .getSingle();
      }

      await updateFolderTree(treeRoot, parentPath);
    }

    // Update paths of files whose parent folders were not updated.
    final staleOrphanFiles = filesByIdMap.values
        .where((f) => !foldersByIdMap.containsKey(f.parentFolderId));
    for (final staleOrphanFile in staleOrphanFiles) {
      final parentPath = await _driveDao
          .folderById(
              driveId: driveId, folderId: staleOrphanFile.parentFolderId.value)
          .map((f) => f.path)
          .getSingleOrNull();

      if (parentPath != null) {
        final filePath = parentPath + '/' + staleOrphanFile.name.value;

        await _driveDao.writeToFile(FileEntriesCompanion(
            id: staleOrphanFile.id,
            driveId: staleOrphanFile.driveId,
            path: Value(filePath)));
      } else {
        print(
            'Stale orphan file ${staleOrphanFile.id.value} parent folder ${staleOrphanFile.parentFolderId.value} could not be found.');
      }
    }
  }

  Future<void> _updateTransactionStatuses() async {
    final pendingTxMap = {
      for (final tx in await _driveDao.pendingTransactions().get()) tx.id: tx,
    };

    final txConfirmations =
        await _arweave.getTransactionConfirmations(pendingTxMap.keys.toList());

    await _driveDao.transaction(() async {
      for (final txId in pendingTxMap.keys) {
        final txConfirmed =
            txConfirmations[txId] >= kRequiredTxConfirmationCount;
        final txNotFound = txConfirmations[txId] < 0;

        var txStatus;

        if (txConfirmed) {
          txStatus = TransactionStatus.confirmed;
        } else if (txNotFound) {
          // Only mark transactions as failed if they are unconfirmed for over 45 minutes
          // as the transaction might not be queryable for right after it was created.
          final abovePendingThreshold = DateTime.now()
                  .difference(pendingTxMap[txId].dateCreated)
                  .inMinutes >
              45;
          if (abovePendingThreshold) {
            txStatus = TransactionStatus.failed;
          }
        }

        if (txStatus != null) {
          await _driveDao.writeToTransaction(
            NetworkTransactionsCompanion(
              id: Value(txId),
              status: Value(txStatus),
            ),
          );
        }
      }
    });
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(SyncFailure());
    super.onError(error, stackTrace);
    emit(SyncIdle());
  }

  @override
  Future<void> close() {
    _syncSub?.cancel();
    return super.close();
  }
}
