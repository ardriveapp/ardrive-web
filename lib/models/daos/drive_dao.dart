import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../../entities/entities.dart';
import '../database/database.dart';
import '../models.dart';

part 'drive_dao.g.dart';

@UseDao(tables: [Drives, FolderEntries, FileEntries])
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final _uuid = Uuid();

  DriveDao(Database db) : super(db);

  Future<Drive> getDriveById(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).getSingle();

  Stream<Drive> watchDriveById(String driveId) =>
      (select(drives)..where((d) => d.id.equals(driveId))).watchSingle();

  Future<SecretKey> getDriveKey(String id, SecretKey profileKey) async {
    final drive = await getDriveById(id);

    if (drive.encryptedKey == null) {
      return null;
    }

    final driveKeyData = await aesGcm.decrypt(
      drive.encryptedKey,
      secretKey: profileKey,
      nonce: Nonce(drive.keyIv),
    );

    return SecretKey(driveKeyData);
  }

  Future<FolderEntry> getFolderById(String driveId, String folderId) =>
      (select(folderEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId)))
          .getSingle();

  Stream<FolderEntry> watchFolderById(String driveId, String folderId) =>
      (select(folderEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId)))
          .watchSingle();

  Future<String> getFolderNameById(String driveId, String folderId) =>
      (select(folderEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId)))
          .map((f) => f.name)
          .getSingle();

  Stream<FolderWithContents> watchFolderContentsById(
      String driveId, String folderId) {
    final folderStream = (select(folderEntries)
          ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId)))
        .watchSingle();

    final subfoldersStream = (select(folderEntries)
          ..where((f) =>
              f.driveId.equals(driveId) & f.parentFolderId.equals(folderId))
          ..orderBy([(f) => OrderingTerm(expression: f.name)]))
        .watch();

    final filesStream = (select(fileEntries)
          ..where((f) =>
              f.driveId.equals(driveId) & f.parentFolderId.equals(folderId))
          ..orderBy([(f) => OrderingTerm(expression: f.name)]))
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

  Stream<FolderWithContents> watchFolderContentsAtPath(
      String driveId, String folderPath) {
    final folderStream = (select(folderEntries)
          ..where((f) => f.driveId.equals(driveId) & f.path.equals(folderPath)))
        .watchSingle();

    final subfoldersStream = (select(folderEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              f.path.like('$folderPath/%') &
              f.path.like('$folderPath/%/%').not())
          ..orderBy([(f) => OrderingTerm(expression: f.name)]))
        .watch();

    final filesStream = (select(fileEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              f.path.like('$folderPath/%') &
              f.path.like('$folderPath/%/%').not())
          ..orderBy([(f) => OrderingTerm(expression: f.name)]))
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

  /// Create a new folder entry.
  /// Returns the id of the created folder.
  Future<String> createFolder({
    String driveId,
    String parentFolderId,
    String folderName,
    String path,
  }) async {
    final id = _uuid.v4();

    await into(folderEntries).insert(
      FolderEntriesCompanion.insert(
        id: id,
        driveId: driveId,
        parentFolderId: Value(parentFolderId),
        name: folderName,
        path: path,
      ),
    );

    return id;
  }

  Future<void> updateFolder(Insertable<FolderEntry> folder) =>
      (update(folderEntries)..whereSamePrimaryKey(folder)).write(folder);

  Future<FileEntry> getFileById(String driveId, String fileId) =>
      (select(fileEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId)))
          .getSingle();

  Future<String> getFileNameById(String driveId, String fileId) =>
      (select(fileEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId)))
          .map((f) => f.name)
          .getSingle();

  Stream<FileEntry> watchFileById(String driveId, String fileId) =>
      (select(fileEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId)))
          .watchSingle();

  Future<String> fileExistsInFolder(String folderId, String filename) async {
    final file = await (select(fileEntries)
          ..where((f) =>
              f.parentFolderId.equals(folderId) & f.name.equals(filename)))
        .getSingle();

    return file != null ? file.id : null;
  }

  Future<void> updateFile(Insertable<FileEntry> file) =>
      (update(fileEntries)..whereSamePrimaryKey(file)).write(file);

  Future<void> writeFileEntity(
    FileEntity entity,
    String path,
  ) =>
      into(fileEntries).insertOnConflictUpdate(
        FileEntriesCompanion.insert(
          id: entity.id,
          driveId: entity.driveId,
          parentFolderId: entity.parentFolderId,
          name: entity.name,
          path: path,
          dataTxId: entity.dataTxId,
          size: entity.size,
          ready: false,
          lastModifiedDate: entity.lastModifiedDate,
        ),
      );
}

class FolderWithContents extends Equatable {
  final FolderEntry folder;
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  FolderWithContents({this.folder, this.subfolders, this.files});

  @override
  List<Object> get props => [folder, subfolders, files];
}
