import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';

import '../blocs.dart';

part 'sync_state.dart';

class SyncCubit extends Cubit<SyncState> {
  final ProfileCubit _profileCubit;
  final ArweaveService _arweave;
  final DrivesDao _drivesDao;
  final DriveDao _driveDao;
  final Database _db;

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
    startSync();
  }

  Future<void> startSync() async {
    emit(SyncInProgress());

    try {
      final profile = _profileCubit.state as ProfileLoaded;

      // Sync in drives owned by the user.
      final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
        profile.wallet,
        profile.password,
      );

      await _drivesDao.updateUserDrives(userDriveEntities, profile.cipherKey);

      // Sync the contents of each drive owned by the user.
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
    final profile = _profileCubit.state as ProfileLoaded;
    final drive = await _driveDao.getDriveById(driveId);
    final driveKey = drive.isPrivate
        ? await _driveDao.getDriveKey(drive.id, profile.cipherKey)
        : null;

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

      await _writeFsEntriesWithPaths(
          driveId, updatedFoldersById, updatedFilesById);

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
        latestRevisions[entity.id] =
            (await _driveDao.getLatestFolderRevisionById(driveId, entity.id))
                .toCompanion(true);
      }

      final revision = FolderRevisionsCompanion.insert(
        folderId: entity.id,
        driveId: entity.driveId,
        name: entity.name,
        parentFolderId: entity.parentFolderId,
        metadataTxId: entity.txId,
        dateCreated: Value(entity.commitTime),
        action: entity.getPerformedRevisionAction(latestRevisions[entity.id]),
      );

      newRevisions.add(revision);
      latestRevisions[entity.id] = revision;
    }

    await _db.batch((b) => b.insertAll(_db.folderRevisions, newRevisions));

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
        latestRevisions[entity.id] =
            (await _driveDao.getLatestFileRevisionById(driveId, entity.id))
                .toCompanion(true);
      }

      final revision = FileRevisionsCompanion.insert(
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

      newRevisions.add(revision);
      latestRevisions[entity.id] = revision;
    }

    await _db.batch((b) => b.insertAll(_db.fileRevisions, newRevisions));

    return latestRevisions.values.toList();
  }

  /// Computes the refreshed folder entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FolderEntriesCompanion>>
      _computeRefreshedFolderEntriesFromRevisions(String driveId,
          List<FolderRevisionsCompanion> revisionsByFolderId) async {
    final updatedFoldersById =
        Map.fromIterable(revisionsByFolderId, key: (f) => f.id).map((id, r) =>
            MapEntry<String, FolderEntriesCompanion>(id, r.toEntryCompanion()));

    for (final folderId in updatedFoldersById.keys) {
      final oldestRevision =
          await _driveDao.getOldestFolderRevisionById(driveId, folderId);

      updatedFoldersById[folderId] = updatedFoldersById[folderId]
          .copyWith(dateCreated: Value(oldestRevision.dateCreated));
    }

    return updatedFoldersById;
  }

    /// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FileEntriesCompanion>>
      _computeRefreshedFileEntriesFromRevisions(String driveId,
          List<FileRevisionsCompanion> revisionsByFileId) async {
    final updatedFilesById =
        Map.fromIterable(revisionsByFileId, key: (f) => f.id).map((id, r) =>
            MapEntry<String, FileEntriesCompanion>(id, r.toEntryCompanion()));

    for (final folderId in updatedFilesById.keys) {
      final oldestRevision =
          await _driveDao.getOldestFileRevisionById(driveId, folderId);

      updatedFilesById[folderId] = updatedFilesById[folderId]
          .copyWith(dateCreated: Value(oldestRevision.dateCreated));
    }

    return updatedFilesById;
  }

  Future<void> _writeFsEntriesWithPaths(
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

      // If the folder details are stale, update them,
      // else just update the path.
      if (foldersByIdMap.containsKey(folderId)) {
        await _driveDao.writeToFolder(
            foldersByIdMap[folderId].copyWith(path: Value(folderPath)));
      } else {
        await _driveDao
            .updateFolderById(driveId, folderId)
            .write(FolderEntriesCompanion(path: Value(folderPath)));
      }

      // Similarly, if the file details are stale, update them,
      // else just update the path.
      for (final staleFileId in node.files.keys) {
        final filePath = folderPath + '/' + node.files[staleFileId];

        if (filesByIdMap.containsKey(staleFileId)) {
          await _driveDao.writeToFile(
              filesByIdMap[staleFileId].copyWith(path: Value(filePath)));
        } else {
          await _driveDao
              .updateFileById(driveId, staleFileId)
              .write(FileEntriesCompanion(path: Value(filePath)));
        }
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
        .where((f) => filesByIdMap[f.parentFolderId] == null);
    for (final staleOrphanFile in staleOrphanFiles) {
      final fileId = staleOrphanFile.id;
      final parentPath = await _driveDao
          .selectFolderById(driveId, staleOrphanFile.parentFolderId.value)
          .map((f) => f.path)
          .getSingle();
      final filePath = parentPath + '/' + staleOrphanFile.name.value;

      if (filesByIdMap.containsKey(fileId)) {
        await _driveDao
            .writeToFile(filesByIdMap[fileId].copyWith(path: Value(filePath)));
      } else {
        await _driveDao.writeToFile(FileEntriesCompanion(
            id: staleOrphanFile.id,
            driveId: staleOrphanFile.driveId,
            path: Value(filePath)));
      }
    }
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    emit(SyncFailure());
    super.onError(error, stackTrace);
    emit(SyncIdle());
  }
}
