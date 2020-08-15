import 'dart:async';

import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../models/models.dart';

part 'drive_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries, FileEntries])
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final uuid = Uuid();

  DriveDao(Database db) : super(db);

  Stream<Drive> watchDrive(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).watchSingle();

  Future<Drive> getDriveById(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).getSingle();

  Future<FolderEntry> getFolderById(String folderId) =>
      (select(folderEntries)..where((d) => d.id.equals(folderId))).getSingle();

  Stream<FolderWithContents> watchFolderWithContents(String folderId) {
    final folderStream = (select(folderEntries)
          ..where((f) => f.id.equals(folderId)))
        .watchSingle();

    final subfoldersStream = (select(folderEntries)
          ..where((f) => f.parentFolderId.equals(folderId)))
        .watch();

    final filesStream = (select(fileEntries)
          ..where((f) => f.parentFolderId.equals(folderId)))
        .watch();

    return Rx.combineLatest3(
      folderStream,
      subfoldersStream,
      filesStream,
      (folder, subfolders, files) => FolderWithContents(
        folder: folder,
        subfolders: subfolders,
        files: files,
      ),
    );
  }

  Stream<FolderWithContents> watchFolderWithContentsAtPath(String folderPath) {
    final folderStream = (select(folderEntries)
          ..where((f) => f.path.equals(folderPath)))
        .watchSingle();

    final subfoldersStream = (select(folderEntries)
          ..where((f) => f.path.like('$folderPath/%'))
          ..where((f) => f.path.like('$folderPath/%/%').not()))
        .watch();

    final filesStream = (select(fileEntries)
          ..where((f) => f.path.like('$folderPath/%'))
          ..where((f) => f.path.like('$folderPath/%/%').not()))
        .watch();

    return Rx.combineLatest3(
      folderStream,
      subfoldersStream,
      filesStream,
      (folder, subfolders, files) => FolderWithContents(
        folder: folder,
        subfolders: subfolders,
        files: files,
      ),
    );
  }

  Future<bool> isDriveEmpty(String driveId) async {
    final folders = await (select(folderEntries)
          ..where((f) => f.driveId.equals(driveId)))
        .get();
    if (folders.length > 0) return false;

    final files = await (select(fileEntries)
          ..where((f) => f.driveId.equals(driveId)))
        .get();
    if (files.length > 0) return false;

    return true;
  }

  Future<bool> isFolderEmpty(String folderId) async {
    final folders = await (select(folderEntries)
          ..where((f) => f.parentFolderId.equals(folderId)))
        .get();
    if (folders.length > 0) return false;

    final files = await (select(fileEntries)
          ..where((f) => f.parentFolderId.equals(folderId)))
        .get();
    if (files.length > 0) return false;

    return true;
  }

  Future<String> fileExistsInFolder(String folderId, String filename) async {
    final file = await (select(fileEntries)
          ..where((f) =>
              f.parentFolderId.equals(folderId) & f.name.equals(filename)))
        .getSingle();

    return file != null ? file.id : null;
  }

  Future<void> createNewFolderEntry(
    String driveId,
    String parentFolderId,
    String folderName,
    String path,
  ) =>
      into(folderEntries).insert(
        FolderEntriesCompanion(
          id: Value(uuid.v4()),
          driveId: Value(driveId),
          parentFolderId: Value(parentFolderId),
          name: Value(folderName),
          path: Value(path),
          hydratedWithInitialEntries: Value(true),
        ),
      );

  Future<void> writeFileEntry(
    String fileId,
    String driveId,
    String parentFolderId,
    String fileName,
    String filePath,
    String fileDataTxId,
    int fileSize,
  ) =>
      into(fileEntries).insertOnConflictUpdate(
        FileEntriesCompanion(
          id: Value(fileId),
          driveId: Value(driveId),
          parentFolderId: Value(parentFolderId),
          name: Value(fileName),
          path: Value(filePath),
          dataTxId: Value(fileDataTxId),
          size: Value(fileSize),
          ready: Value(false),
        ),
      );
}

class FolderWithContents {
  final FolderEntry folder;
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  FolderWithContents({this.folder, this.subfolders, this.files});
}
