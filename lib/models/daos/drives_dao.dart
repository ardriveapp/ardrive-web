import 'package:drive/services/services.dart';
import 'package:moor/moor.dart';
import 'package:uuid/uuid.dart';

import '../../entities/entities.dart';
import '../database/database.dart';
import '../models.dart';

part 'drives_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries, FileEntries])
class DrivesDao extends DatabaseAccessor<Database> with _$DrivesDaoMixin {
  final uuid = Uuid();

  DrivesDao(Database db) : super(db);

  Future<List<Drive>> getAllDrives() => select(drives).get();
  Stream<List<Drive>> watchAllDrives() => select(drives).watch();

  /// Creates a drive with its accompanying root folder.
  /// Return a list with two ids, the first being the drive id and the second being the root folder id.
  Future<List<String>> createDrive(
      {@required String name,
      @required String ownerAddress,
      @required String privacy}) async {
    final driveId = uuid.v4();
    final rootFolderId = uuid.v4();

    await batch((batch) {
      batch.insert(
        drives,
        DrivesCompanion.insert(
          id: driveId,
          name: name,
          ownerAddress: ownerAddress,
          rootFolderId: rootFolderId,
          privacy: privacy,
        ),
      );

      batch.insert(
        folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: name,
          path: '',
        ),
      );
    });

    return [driveId, rootFolderId];
  }

  Future<void> attachDrive(String name, DriveEntity entity) =>
      into(drives).insert(
        DrivesCompanion.insert(
          id: entity.id,
          name: name,
          ownerAddress: entity.ownerAddress,
          rootFolderId: entity.rootFolderId,
        ),
      );

  Future<void> applyEntityHistory(
          String driveId, DriveEntityHistory entityHistory) =>
      transaction(() async {
        final drive = await (select(drives)..where((d) => d.id.equals(driveId)))
            .getSingle();

        // Create maps of folders and files whose contents were updated on the network, keyed by their ids.
        final updatedFolders = <String, FolderEntriesCompanion>{};
        final updatedFiles = <String, FileEntriesCompanion>{};

        // Iterate through the history in reverse order to get the latest entity data we can write in.
        for (final block in entityHistory.blockHistory.reversed) {
          for (final entity in block.entities.reversed) {
            // Ignore the entity if it did not come from the drive owner.
            if (drive.ownerAddress != entity.ownerAddress) continue;

            if (entity is FolderEntity) {
              if (updatedFolders.containsKey(entity.id)) continue;

              updatedFolders[entity.id] = FolderEntriesCompanion.insert(
                id: entity.id,
                driveId: entity.driveId,
                parentFolderId: Value(entity.parentFolderId),
                name: entity.name,
                path: '',
              );
            } else if (entity is FileEntity) {
              if (updatedFiles.containsKey(entity.id)) continue;

              updatedFiles[entity.id] = FileEntriesCompanion.insert(
                id: entity.id,
                driveId: entity.driveId,
                parentFolderId: entity.parentFolderId,
                name: entity.name,
                dataTxId: entity.dataTxId,
                size: entity.size,
                ready: true,
                path: '',
              );
            }
          }
        }

        // Write in the new folder and file contents without their paths.
        await batch((b) {
          b.insertAllOnConflictUpdate(
              folderEntries, updatedFolders.values.toList());
          b.insertAllOnConflictUpdate(
              fileEntries, updatedFiles.values.toList());
        });

        // Construct a tree of the updated folders and files for path generation.
        final staleFolderTree = <StaleFolderNode>[];

        Future<StaleFolderNode> getStaleFolderTree(
            FolderEntriesCompanion folder) async {
          final folderId = folder.id.value;

          // Get all the subfolders and files of this folder that are now stale.
          final staleSubfolders = await (select(folderEntries)
                ..where((f) => f.parentFolderId.equals(folderId)))
              .get();
          final staleFolderFiles = await (select(fileEntries)
                ..where((f) => f.parentFolderId.equals(folderId)))
              .get();
          final staleFolderFilesMap = {
            for (var f in staleFolderFiles) f.id: f.name
          };

          return StaleFolderNode(
            folder,
            await Future.wait(
              staleSubfolders.map(
                (f) => getStaleFolderTree(
                  updatedFolders[f.id] ??
                      FolderEntriesCompanion.insert(
                        id: f.id,
                        driveId: f.driveId,
                        parentFolderId: Value(f.parentFolderId),
                        name: f.name,
                        path: '',
                      ),
                ),
              ),
            ),
            staleFolderFilesMap,
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

          await (update(folderEntries)
                ..where((f) => f.id.equals(node.folder.id.value)))
              .write(FolderEntriesCompanion(path: Value(folderPath)));

          for (final staleFileId in node.files.keys) {
            final filePath = folderPath + '/' + node.files[staleFileId];
            await (update(fileEntries)..where((f) => f.id.equals(staleFileId)))
                .write(FileEntriesCompanion(path: Value(filePath)));
          }

          for (final staleFolder in node.subfolders) {
            await updateFolderTree(staleFolder, folderPath);
          }
        }

        for (final treeRoot in staleFolderTree) {
          // Get the path of this folder's parent.
          String parentPath;
          if (treeRoot.folder.parentFolderId.value != null) {
            parentPath = '';
          } else {
            parentPath = await (select(folderEntries)
                  ..where(
                      (f) => f.id.equals(treeRoot.folder.parentFolderId.value)))
                .map((f) => f.path)
                .getSingle();
          }

          await updateFolderTree(treeRoot, parentPath);
        }

        // Update paths of files whose parent folders were not updated.
        final staleOrphanFiles = updatedFiles.values
            .where((f) => updatedFolders[f.parentFolderId] == null);
        for (final staleOrphanFile in staleOrphanFiles) {
          final parentPath = await (select(folderEntries)
                ..where(
                    (f) => f.id.equals(staleOrphanFile.parentFolderId.value)))
              .map((f) => f.path)
              .getSingle();

          await (update(fileEntries)..whereSamePrimaryKey(staleOrphanFile))
              .write(FileEntriesCompanion(
                  path: Value(parentPath + '/' + staleOrphanFile.name.value)));
        }

        await (update(drives)..whereSamePrimaryKey(drive)).write(
            DrivesCompanion(
                latestSyncedBlock: Value(entityHistory.latestBlockHeight)));
      });
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
