import 'dart:async';

import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../database.dart';
import '../models/models.dart';

part 'drive_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries, FileEntries])
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final uuid = Uuid();

  DriveDao(Database db) : super(db);

  Stream<Drive> watchDrive(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).watchSingle();

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
        ),
      );

  Future<void> createNewFileEntry(
    String driveId,
    String parentFolderId,
    String fileName,
    String filePath,
    int fileSize,
  ) =>
      into(fileEntries).insert(
        FileEntriesCompanion(
          id: Value(uuid.v4()),
          driveId: Value(driveId),
          parentFolderId: Value(parentFolderId),
          name: Value(fileName),
          path: Value(filePath),
          size: Value(fileSize),
        ),
      );
}

class FolderWithContents {
  final FolderEntry folder;
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  FolderWithContents({this.folder, this.subfolders, this.files});
}
