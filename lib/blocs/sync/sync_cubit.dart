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
  final ProfileBloc _profileBloc;
  final ArweaveService _arweave;
  final DrivesDao _drivesDao;
  final DriveDao _driveDao;
  final Database _db;

  SyncCubit({
    @required ProfileBloc profileBloc,
    @required ArweaveService arweave,
    @required DrivesDao drivesDao,
    @required DriveDao driveDao,
    @required Database db,
  })  : _profileBloc = profileBloc,
        _arweave = arweave,
        _drivesDao = drivesDao,
        _driveDao = driveDao,
        _db = db,
        super(SyncIdle()) {
    startSync();
  }

  Future<void> startSync() async {
    emit(SyncInProgress());

    final profile = _profileBloc.state as ProfileLoaded;

    // Sync in drives owned by the user.
    final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
      profile.wallet,
      profile.password,
    );

    await _drivesDao.updateUserDrives(userDriveEntities, profile.cipherKey);

    // Sync the contents of each drive owned by the user.
    final userDrives = await _drivesDao.getAllDrives();

    final driveSyncProcesses = userDrives.map((drive) => _syncDrive(drive));
    await Future.wait(driveSyncProcesses);

    emit(SyncIdle());
  }

  Future<void> _syncDrive(Drive drive) async {
    final profile = _profileBloc.state as ProfileLoaded;
    final driveKey = drive.isPrivate
        ? await _driveDao.getDriveKey(drive.id, profile.cipherKey)
        : null;

    final entityHistory = await _arweave.getNewEntitiesForDriveSinceBlock(
      drive.id,
      // We should start syncing from the block after the latest one we already synced from.
      drive.latestSyncedBlock + 1,
      driveKey,
    );

    // The latest and oldest version of folder/file entities which were updated, keyed by their ids.
    final latestFolderEntities = <String, FolderEntity>{};
    final latestFileEntities = <String, FileEntity>{};
    final oldestFolderEntities = <String, FolderEntity>{};
    final oldestFileEntities = <String, FileEntity>{};

    // Construct maps of the latest and oldest unique entities.
    // Iterates the entities from oldest -> latest.
    for (final block in entityHistory.blockHistory) {
      for (final entity in block.entities) {
        // Ignore the entity if it did not come from the drive owner.
        if (drive.ownerAddress != entity.ownerAddress) continue;

        if (entity is FolderEntity) {
          latestFolderEntities[entity.id] = entity;
          if (!oldestFolderEntities.containsKey(entity.id)) {
            oldestFolderEntities[entity.id] = entity;
          }
        } else if (entity is FileEntity) {
          latestFileEntities[entity.id] = entity;
          if (!oldestFileEntities.containsKey(entity.id)) {
            oldestFileEntities[entity.id] = entity;
          }
        }
      }
    }

    final updatedFolders = latestFolderEntities
        .map((id, entity) => MapEntry<String, FolderEntriesCompanion>(
              id,
              FolderEntriesCompanion.insert(
                id: entity.id,
                driveId: entity.driveId,
                parentFolderId: Value(entity.parentFolderId),
                name: entity.name,
                path: '',
                dateCreated: Value(oldestFolderEntities[entity.id].commitTime),
                lastUpdated: Value(entity.commitTime),
              ),
            ));
    final updatedFiles = latestFileEntities
        .map((id, entity) => MapEntry<String, FileEntriesCompanion>(
              id,
              FileEntriesCompanion.insert(
                id: entity.id,
                driveId: entity.driveId,
                parentFolderId: entity.parentFolderId,
                name: entity.name,
                dataTxId: entity.dataTxId,
                size: entity.size,
                path: '',
                dateCreated: Value(oldestFileEntities[entity.id].commitTime),
                lastUpdated: Value(entity.commitTime),
                lastModifiedDate: entity.lastModifiedDate,
              ),
            ));

    await _db.transaction(() async {
      // Write in the new folder and file contents without their paths
      // and don't update the `dateCreated` if the entry already exists.
      await _db.batch((b) {
        for (final folder in updatedFolders.values) {
          b.insert(_db.folderEntries, folder,
              onConflict: DoUpdate((_) => folder.copyWith(dateCreated: null)));
        }
        for (final file in updatedFiles.values) {
          b.insert(_db.fileEntries, file,
              onConflict: DoUpdate((_) => file.copyWith(dateCreated: null)));
        }
      });

      // Construct a tree of the updated folders and files for path generation.
      final staleFolderTree = <StaleFolderNode>[];

      // Constructs a tree of folders and files that are children of the specified folder.
      Future<StaleFolderNode> getStaleFolderTree(
          FolderEntriesCompanion folder) async {
        final folderId = folder.id.value;

        // Get all the subfolders and files of this folder that are now stale.
        final staleSubfolders = await _driveDao
            .selectFoldersByParentFolderId(drive.id, folderId)
            .get();
        final staleFilesMap = {
          await for (var f in _driveDao
              .selectFilesByParentFolderId(drive.id, folderId)
              .get()
              .asStream()
              .expand((f) => f))
            f.id: f.name
        };

        return StaleFolderNode(
          folder,
          // Recursively get the stale contents of this folder's subfolders.
          await Future.wait(staleSubfolders.map((f) =>
              getStaleFolderTree(updatedFolders[f.id] ?? f.toCompanion(true)))),
          staleFilesMap,
        );
      }

      for (final folder in updatedFolders.values) {
        final tree = await getStaleFolderTree(folder);

        var newTreeIsSubsetOfExisting = false;
        var newTreeIsSupersetOfExisting = false;
        for (final existingTree in staleFolderTree) {
          if (existingTree.searchForFolder(tree.folder.id.value) != null) {
            newTreeIsSubsetOfExisting = true;
          } else if (tree.searchForFolder(existingTree.folder.id.value) !=
              null) {
            staleFolderTree.remove(existingTree);
            staleFolderTree.add(tree);
            newTreeIsSupersetOfExisting = true;
          }
        }

        if (!newTreeIsSubsetOfExisting && !newTreeIsSupersetOfExisting) {
          staleFolderTree.add(tree);
        }
      }

      Future<void> updateFolderTree(
          StaleFolderNode node, String parentPath) async {
        // If this is the root folder, we should not include its name as part of the path.
        final folderPath = node.folder.parentFolderId.value != null
            ? parentPath + '/' + node.folder.name.value
            : '';

        await _driveDao
            .updateFolderById(drive.id, node.folder.id.value)
            .write(FolderEntriesCompanion(path: Value(folderPath)));

        for (final staleFileId in node.files.keys) {
          final filePath = folderPath + '/' + node.files[staleFileId];
          await _driveDao
              .updateFileById(drive.id, staleFileId)
              .write(FileEntriesCompanion(path: Value(filePath)));
        }

        for (final staleFolder in node.subfolders) {
          await updateFolderTree(staleFolder, folderPath);
        }
      }

      for (final treeRoot in staleFolderTree) {
        // Get the path of this folder's parent.
        String parentPath;
        if (treeRoot.folder.parentFolderId.value == null) {
          parentPath = '';
        } else {
          parentPath = await _driveDao
              .selectFolderById(drive.id, treeRoot.folder.parentFolderId.value)
              .map((f) => f.path)
              .getSingle();
        }

        await updateFolderTree(treeRoot, parentPath);
      }

      // Update paths of files whose parent folders were not updated.
      final staleOrphanFiles = updatedFiles.values
          .where((f) => updatedFolders[f.parentFolderId] == null);
      for (final staleOrphanFile in staleOrphanFiles) {
        final parentPath = await _driveDao
            .selectFolderById(drive.id, staleOrphanFile.parentFolderId.value)
            .map((f) => f.path)
            .getSingle();

        await _driveDao.writeToFile(FileEntriesCompanion(
            id: staleOrphanFile.id,
            driveId: staleOrphanFile.driveId,
            path: Value(parentPath + '/' + staleOrphanFile.name.value)));
      }

      await _driveDao.writeToDrive(DrivesCompanion(
          id: Value(drive.id),
          latestSyncedBlock: Value(entityHistory.latestBlockHeight)));
    });
  }
}

class StaleFolderNode {
  final FolderEntriesCompanion folder;
  final List<StaleFolderNode> subfolders;
  final Map<String, String> files;

  StaleFolderNode(this.folder, this.subfolders, this.files);

  StaleFolderNode searchForFolder(String folderId) {
    if (folder.id.value == folderId) return this;

    for (final subfolder in subfolders) {
      return subfolder.searchForFolder(folderId);
    }

    return null;
  }
}
