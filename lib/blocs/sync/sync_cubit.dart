import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
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
  final DrivesDao _drivesDao;
  final DriveDao _driveDao;
  final Database _db;

  StreamSubscription _syncSub;

  SyncCubit({
    @required ProfileCubit profileCubit,
    @required ArweaveService arweave,
    @required DrivesDao drivesDao,
    @required DriveDao driveDao,
    @required Database db,
  })  : _profileCubit = profileCubit,
        _arweave = arweave,
        _drivesDao = drivesDao,
        _driveDao = driveDao,
        _db = db,
        super(SyncIdle()) {
    // Sync the user's drives on start and periodically.
    _syncSub = interval(const Duration(minutes: 2))
        .startWith(null)
        .listen((_) => startSync());
  }

  Future<void> startSync() async {
    emit(SyncInProgress());

    try {
      final profile = _profileCubit.state;

      // Only sync in drives owned by the user if they're logged in.
      if (profile is ProfileLoggedIn) {
        final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
            profile.wallet, profile.password);

        await _drivesDao.updateUserDrives(userDriveEntities, profile.cipherKey);
      }

      // Sync the contents of each drive attached in the app.
      final driveIds =
          await _drivesDao.selectAllDrives().map((d) => d.id).get();
      final driveSyncProcesses = driveIds.map((driveId) => _syncDrive(driveId));
      await Future.wait(driveSyncProcesses);
    } catch (err) {
      addError(err);
    }

    emit(SyncIdle());
  }

  Future<void> _syncDrive(String driveId) async {
    //final profile = _profileCubit.state as ProfileLoggedIn;
    final drive = await _driveDao.getDriveById(driveId);

    if (drive.isPrivate) {
      return;
    }

    final driveKey = drive.isPrivate ? null : null;

    final entityHistory = await _arweave.getNewEntitiesForDriveSinceBlock(
      drive.id,
      // We should start syncing from the block after the latest one we already synced from.
      drive.latestSyncedBlock + 1,
      driveKey,
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

      await _generateFsEntryPaths(
          driveId, updatedFoldersById, updatedFilesById);

      await _updateRevisionTransactionStatuses(driveId);

      await _driveDao.writeToDrive(DrivesCompanion(
          id: Value(drive.id),
          latestSyncedBlock: Value(entityHistory.latestBlockHeight)));
    });
  }

  /// Computes the new folder revisions from the provided entities, inserts them into the database, and returns them.
  Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions(
      String driveId, Iterable<FolderEntity> newEntities) async {
    // The latest folder revisions, keyed by their entity ids.
    final latestRevisions = <String, FolderRevisionsCompanion>{};

    final newRevisions = <FolderRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        latestRevisions[entity.id] = await _driveDao
            .getLatestFolderRevisionById(driveId, entity.id)
            .then((r) => r?.toCompanion(true));
      }

      final revision = FolderRevisionsCompanion.insert(
        id: entity.txId,
        folderId: entity.id,
        driveId: entity.driveId,
        name: entity.name,
        parentFolderId: Value(entity.parentFolderId),
        metadataTxId: entity.txId,
        dateCreated: Value(entity.commitTime),
        action: entity.getPerformedRevisionAction(latestRevisions[entity.id]),
      );

      if (revision.action.value == null) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id] = revision;
    }

    await _db.batch(
        (b) => b.insertAllOnConflictUpdate(_db.folderRevisions, newRevisions));

    return latestRevisions.values.toList();
  }

  /// Computes the new file revisions from the provided entities, inserts them into the database, and returns them.
  Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions(
      String driveId, Iterable<FileEntity> newEntities) async {
    // The latest file revisions, keyed by their entity ids.
    final latestRevisions = <String, FileRevisionsCompanion>{};

    final newRevisions = <FileRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        latestRevisions[entity.id] = await _driveDao
            .getLatestFileRevisionById(driveId, entity.id)
            .then((r) => r?.toCompanion(true));
      }

      final revision = FileRevisionsCompanion.insert(
        id: entity.txId,
        fileId: entity.id,
        driveId: entity.driveId,
        name: entity.name,
        parentFolderId: entity.parentFolderId,
        size: entity.size,
        lastModifiedDate: entity.lastModifiedDate,
        metadataTxId: entity.txId,
        dataTxId: entity.dataTxId,
        dateCreated: Value(entity.commitTime),
        action: entity.getPerformedRevisionAction(latestRevisions[entity.id]),
      );

      if (revision.action.value == null) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id] = revision;
    }

    await _db.batch(
        (b) => b.insertAllOnConflictUpdate(_db.fileRevisions, newRevisions));

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
      final oldestRevision =
          await _driveDao.getOldestFolderRevisionById(driveId, folderId);

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
      final oldestRevision =
          await _driveDao.getOldestFileRevisionById(driveId, fileId);

      updatedFilesById[fileId] = updatedFilesById[fileId].copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFilesById[fileId].dateCreated));
    }

    return updatedFilesById;
  }

  /// Generates paths for the folders (and their subchildren) and files provided.
  Future<void> _generateFsEntryPaths(
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
            .selectFolderById(driveId, treeRoot.folder.parentFolderId)
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
          .selectFolderById(driveId, staleOrphanFile.parentFolderId.value)
          .map((f) => f.path)
          .getSingle();

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

  Future<void> _updateRevisionTransactionStatuses(String driveId) async {
    final unconfirmedFolderRevisions =
        await _driveDao.selectUnconfirmedFolderRevisions(driveId).get();
    final unconfirmedFileRevisions =
        await _driveDao.selectUnconfirmedFileRevisions(driveId).get();

    // Construct a list of revisions with transactions that are unconfirmed,
    // filtering out ones that are already confirmed.
    final unconfirmedRevisionsByTxId = Map.fromEntries(
        unconfirmedFolderRevisions
            .map((r) => MapEntry<String, Object>(r.metadataTxId, r))
            .followedBy(unconfirmedFileRevisions
                .where((r) => r.metadataTxStatus == TransactionStatus.pending)
                .map((r) => MapEntry<String, Object>(r.metadataTxId, r)))
            .followedBy(unconfirmedFileRevisions
                .where((r) => r.dataTxStatus == TransactionStatus.pending)
                .map((r) => MapEntry<String, Object>(r.dataTxId, r))));

    final txConfirmations = await _arweave
        .getTransactionConfirmations(unconfirmedRevisionsByTxId.keys.toList());
    final txStatuses =
        txConfirmations.map<String, String>((txId, confirmations) {
      if (confirmations >= kRequiredTxConfirmationCount) {
        return MapEntry(txId, TransactionStatus.confirmed);
      } else if (confirmations >= 0) {
        return MapEntry(txId, TransactionStatus.pending);
      } else {
        final revision = unconfirmedRevisionsByTxId[txId];

        // Only mark revisions as failed if they are unconfirmed for over 45 minutes
        // as the transaction might not be queryable for right after it was created.
        var abovePendingThreshold = false;

        if (revision is FileRevision) {
          abovePendingThreshold =
              DateTime.now().difference(revision.dateCreated).inMinutes > 45;
        } else if (revision is FolderRevision) {
          abovePendingThreshold =
              DateTime.now().difference(revision.dateCreated).inMinutes > 45;
        }

        return MapEntry(
          txId,
          abovePendingThreshold
              ? TransactionStatus.failed
              : TransactionStatus.pending,
        );
      }
    });

    await _driveDao.transaction(() async {
      for (final folderRevision in unconfirmedFolderRevisions) {
        await _driveDao.writeToFolderRevision(
          FolderRevisionsCompanion(
            id: Value(folderRevision.id),
            metadataTxStatus: Value(txStatuses[folderRevision.metadataTxId]),
          ),
        );
      }

      for (final fileRevision in unconfirmedFileRevisions) {
        // If a transaction does not have a corresponding confirmation status, it was filtered out above and
        // has already been confirmed.
        final metadataTxStatus =
            txStatuses.containsKey(fileRevision.metadataTxId)
                ? txStatuses[fileRevision.metadataTxId]
                : TransactionStatus.confirmed;

        final dataTxStatus = txStatuses.containsKey(fileRevision.dataTxId)
            ? txStatuses[fileRevision.dataTxId]
            : TransactionStatus.confirmed;

        await _driveDao.writeToFileRevision(
          FileRevisionsCompanion(
            id: Value(fileRevision.id),
            metadataTxStatus: Value(metadataTxStatus),
            dataTxStatus: Value(dataTxStatus),
          ),
        );
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
