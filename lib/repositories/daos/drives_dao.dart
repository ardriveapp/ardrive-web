import 'package:drive/repositories/repositories.dart';
import 'package:moor/moor.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/models.dart';

part 'drives_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries, FileEntries])
class DrivesDao extends DatabaseAccessor<Database> with _$DrivesDaoMixin {
  final uuid = Uuid();

  DrivesDao(Database db) : super(db);

  Stream<List<Drive>> watchAllDrives() => select(drives).watch();

  Future<void> createDrive({@required String name}) => batch((batch) {
        final driveId = uuid.v4();
        final rootFolderId = uuid.v4();

        batch.insert(
          drives,
          DrivesCompanion(
            id: Value(driveId),
            name: Value(name),
            rootFolderId: Value(rootFolderId),
          ),
        );

        batch.insert(
          folderEntries,
          FolderEntriesCompanion(
            id: Value(rootFolderId),
            driveId: Value(driveId),
            name: Value(name),
            path: Value('/$name'),
          ),
        );
      });

  Future<void> attachDrive(String name, DriveEntity driveEntity) =>
      into(drives).insert(DrivesCompanion(
          id: Value(driveEntity.id),
          name: Value(name),
          rootFolderId: Value(driveEntity.rootFolderId)));

  Future<void> updateStaleModels(UpdatedEntities entities) =>
      transaction(() async {
        for (final driveEntity in entities.drives.values) {
          await (update(drives)..where((d) => d.id.equals(driveEntity.id)))
              .write(
            DrivesCompanion(
              rootFolderId: Value(driveEntity.rootFolderId),
            ),
          );
        }

        for (final folderEntity in entities.folders.values)
          await into(folderEntries).insert(
              FolderEntriesCompanion(
                id: Value(folderEntity.id),
                driveId: Value(folderEntity.driveId),
                parentFolderId: Value(folderEntity.parentFolderId),
                name: Value(folderEntity.name),
                path: Value('/'),
              ),
              onConflict: DoUpdate((_) => FolderEntriesCompanion(
                    parentFolderId: Value(folderEntity.parentFolderId),
                  )));

        final staleFolders = <StaleFolderNode>[];

        Future<StaleFolderNode> getStaleFolderTree(
            String folderId, FolderEntity entity) async {
          final staleSubfolders = await (select(folderEntries)
                ..where((f) => f.parentFolderId.equals(folderId)))
              .get();

          final staleFiles = Map<String, FileEntity>.fromIterable(
              await (select(fileEntries)
                    ..where((f) => f.parentFolderId.equals(folderId)))
                  .map((f) => f.id)
                  .get(),
              key: (id) => id,
              value: (_) => null)
            ..addAll(
              Map<String, FileEntity>.from(entities.files)
                ..removeWhere((k, f) => f.parentFolderId != folderId),
            );

          return StaleFolderNode(
              folderId,
              entity,
              await Future.wait(
                  staleSubfolders.map((f) => getStaleFolderTree(f.id, null))),
              staleFiles);
        }

        for (final folderEntity in entities.folders.values) {
          final tree = await getStaleFolderTree(folderEntity.id, folderEntity);

          bool newTreeIsSubsetOfExisting = false;
          bool newTreeIsSupersetOfExisting = false;
          for (final existingTree in staleFolders)
            // Is the new tree a subset of an existing tree?
            if (existingTree.searchForFolder(tree.id) != null)
              newTreeIsSubsetOfExisting = true;
            // Is the new tree a superset of an existing tree?
            else if (tree.searchForFolder(existingTree.id) != null) {
              staleFolders.remove(existingTree);
              staleFolders.add(tree);
              newTreeIsSupersetOfExisting = true;
            }

          if (!newTreeIsSubsetOfExisting && !newTreeIsSupersetOfExisting)
            staleFolders.add(tree);
        }

        Future<void> updateFolderTree(
            StaleFolderNode node, String parentPath) async {
          final folderName = node.entity?.name ??
              await (select(folderEntries)..where((f) => f.id.equals(node.id)))
                  .map((f) => f.name)
                  .getSingle();

          final driveId = node.entity?.driveId ??
              await (select(folderEntries)..where((f) => f.id.equals(node.id)))
                  .map((f) => f.driveId)
                  .getSingle();

          final newPath = parentPath + '/' + folderName;

          await into(folderEntries).insertOnConflictUpdate(
            FolderEntriesCompanion(
              id: Value(node.id),
              driveId: Value(driveId),
              name: Value(folderName),
              path: Value(newPath),
            ),
          );

          for (final staleFileId in node.files.keys) {
            final fileName = entities.files[staleFileId]?.name ??
                await (select(fileEntries)
                      ..where((f) => f.id.equals(staleFileId)))
                    .map((f) => f.name)
                    .getSingle();

            final filePath = newPath + '/' + fileName;

            if (node.files[staleFileId] != null) {
              await into(fileEntries)
                  .insertOnConflictUpdate(FileEntriesCompanion(
                id: Value(staleFileId),
                driveId: Value(node.files[staleFileId].driveId),
                parentFolderId: Value(node.files[staleFileId].parentFolderId),
                name: Value(fileName),
                path: Value(filePath),
                dataTxId: Value(node.files[staleFileId].dataTxId),
                size: Value(node.files[staleFileId].size),
                ready: Value(true),
              ));
            } else {
              await (update(fileEntries)
                    ..where((f) => f.id.equals(staleFileId)))
                  .write(FileEntriesCompanion(path: Value(filePath)));
            }
          }

          for (final staleFolder in node.subfolders)
            await updateFolderTree(staleFolder, newPath);
        }

        for (final staleFolder in staleFolders) {
          final parentFolderId = await (select(folderEntries)
                ..where((f) => f.id.equals(staleFolder.id)))
              .map((f) => f.parentFolderId)
              .getSingle();

          final parentPath = parentFolderId != null
              ? await (select(folderEntries)
                    ..where((f) => f.id.equals(parentFolderId)))
                  .map((f) => f.path)
                  .getSingle()
              : '';

          await updateFolderTree(staleFolder, parentPath);
        }
      });
}

class StaleFolderNode {
  final String id;
  final FolderEntity entity;
  final List<StaleFolderNode> subfolders;
  final Map<String, FileEntity> files;

  StaleFolderNode(this.id, this.entity, this.subfolders, this.files);

  StaleFolderNode searchForFolder(String folderId) {
    if (id == folderId) return this;

    for (final subfolder in subfolders)
      return subfolder.searchForFolder(folderId);

    return null;
  }
}
