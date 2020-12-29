import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../../models.dart';

part 'drive_dao.g.dart';
part 'folder_node.dart';
part 'folder_with_contents.dart';

@UseDao(tables: [
  Drives,
  FolderEntries,
  FolderRevisions,
  FileEntries,
  FileRevisions
])
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final _uuid = Uuid();

  DriveDao(Database db) : super(db);

  SimpleSelectStatement<Drives, Drive> selectDriveById(String driveId) =>
      select(drives)..where((d) => d.id.equals(driveId));

  Future<Drive> getDriveById(String driveId) =>
      selectDriveById(driveId).getSingle();

  Stream<Drive> watchDriveById(String driveId) =>
      selectDriveById(driveId).watchSingle();

  /// Returns the encryption key for the specified drive.
  ///
  /// `null` if the drive is public and unencrypted.
  Future<SecretKey> getDriveKey(String driveId, SecretKey profileKey) async {
    final drive = await getDriveById(driveId);

    if (drive.encryptedKey == null) {
      return null;
    }

    final driveKeyData = await aesGcm.decrypt(
      drive.encryptedKey,
      secretKey: profileKey,
      nonce: Nonce(drive.keyEncryptionIv),
    );

    return SecretKey(driveKeyData);
  }

  /// Returns the encryption key for the specified file.
  ///
  /// `null` if the file is public and unencrypted.
  Future<SecretKey> getFileKey(
    String driveId,
    String fileId,
    SecretKey profileKey,
  ) async {
    final driveKey = await getDriveKey(driveId, profileKey);
    if (driveKey != null) {
      return deriveFileKey(driveKey, fileId);
    } else {
      return null;
    }
  }

  Future<void> writeToDrive(Insertable<Drive> drive) =>
      (update(drives)..whereSamePrimaryKey(drive)).write(drive);

  SimpleSelectStatement<FolderEntries, FolderEntry> selectFolderById(
          String driveId, String folderId) =>
      (select(folderEntries)
        ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId)));

  Future<FolderEntry> getFolderById(String driveId, String folderId) =>
      selectFolderById(driveId, folderId).getSingle();

  Stream<FolderEntry> watchFolderById(String driveId, String folderId) =>
      selectFolderById(driveId, folderId).watchSingle();

  SimpleSelectStatement<FolderEntries, FolderEntry>
      selectFoldersByParentFolderId(String driveId, String parentFolderId) =>
          (select(folderEntries)
            ..where((f) =>
                f.driveId.equals(driveId) &
                f.parentFolderId.equals(parentFolderId)));

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

  SimpleSelectStatement<FolderEntries, FolderEntry> selectFolderInFolderByName(
          String driveId, String folderId, String folderName) =>
      (select(folderEntries)
        ..where((f) =>
            f.driveId.equals(driveId) &
            f.parentFolderId.equals(folderId) &
            f.name.equals(folderName)));

  UpdateStatement<FolderEntries, FolderEntry> updateFolderById(
          String driveId, String folderId) =>
      update(folderEntries)
        ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId));

  Future<void> writeToFolder(Insertable<FolderEntry> folder) =>
      (update(folderEntries)..whereSamePrimaryKey(folder)).write(folder);

  /// Constructs a tree of folders and files that are children of the specified folder.
  Future<FolderNode> getFolderTree(String driveId, String rootFolderId) async {
    final rootFolder = await getFolderById(driveId, rootFolderId);

    Future<FolderNode> getFolderChildren(FolderEntry parentFolder) async {
      final subfolders =
          await selectFoldersByParentFolderId(driveId, parentFolder.id).get();

      return FolderNode(
        folder: parentFolder,
        // Get the children of this folder's subfolders.
        subfolders:
            await Future.wait(subfolders.map((f) => getFolderChildren(f))),
        files: {
          await for (var f
              in selectFilesByParentFolderId(driveId, parentFolder.id)
                  .get()
                  .asStream()
                  .expand((f) => f))
            f.id: f.name
        },
      );
    }

    return getFolderChildren(rootFolder);
  }

  SimpleSelectStatement<FileEntries, FileEntry> selectFileById(
          String driveId, String fileId) =>
      (select(fileEntries)
        ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId)));

  Future<FileEntry> getFileById(String driveId, String fileId) =>
      selectFileById(driveId, fileId).getSingle();

  Stream<FileEntry> watchFileById(String driveId, String fileId) =>
      (select(fileEntries)
            ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId)))
          .watchSingle();

  SimpleSelectStatement<FileEntries, FileEntry> selectFileInFolderByName(
          String driveId, String folderId, String fileName) =>
      (select(fileEntries)
        ..where((f) =>
            f.driveId.equals(driveId) &
            f.parentFolderId.equals(folderId) &
            f.name.equals(fileName)));

  SimpleSelectStatement<FileEntries, FileEntry> selectFilesByParentFolderId(
          String driveId, String parentFolderId) =>
      (select(fileEntries)
        ..where((f) =>
            f.driveId.equals(driveId) &
            f.parentFolderId.equals(parentFolderId)));

  UpdateStatement<FileEntries, FileEntry> updateFileById(
          String driveId, String fileId) =>
      update(fileEntries)
        ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId));

  Future<void> writeToFile(Insertable<FileEntry> file) =>
      (update(fileEntries)..whereSamePrimaryKey(file)).write(file);

  Future<void> writeFileEntity(
    FileEntity entity,
    String path,
  ) {
    final companion = FileEntriesCompanion.insert(
      id: entity.id,
      driveId: entity.driveId,
      parentFolderId: entity.parentFolderId,
      name: entity.name,
      path: path,
      dataTxId: entity.dataTxId,
      size: entity.size,
      lastModifiedDate: entity.lastModifiedDate,
    );

    return into(fileEntries).insert(
      companion,
      onConflict: DoUpdate((_) => companion.copyWith(dateCreated: null)),
    );
  }

  SimpleSelectStatement<FolderRevisions, FolderRevision>
      selectUnconfirmedFolderRevisions(String driveId) =>
          select(folderRevisions)
            ..where((r) =>
                r.driveId.equals(driveId) &
                r.metadataTxStatus.equals(TransactionStatus.pending));

  SimpleSelectStatement<FolderRevisions, FolderRevision>
      selectFolderRevisionsById(String driveId, String folderId) =>
          (select(folderRevisions)
            ..where((f) =>
                f.driveId.equals(driveId) & f.folderId.equals(folderId)));

  SimpleSelectStatement<FolderRevisions, FolderRevision>
      selectLatestFolderRevisionsById(String driveId, String folderId) =>
          selectFolderRevisionsById(driveId, folderId)
            ..orderBy([
              (f) => OrderingTerm(
                  expression: f.dateCreated, mode: OrderingMode.desc)
            ]);

  Future<FolderRevision> getLatestFolderRevisionById(
          String driveId, String folderId) =>
      (selectLatestFolderRevisionsById(driveId, folderId)..limit(1))
          .getSingle();

  Future<FolderRevision> getOldestFolderRevisionById(
          String driveId, String folderId) =>
      (selectFolderRevisionsById(driveId, folderId)
            ..orderBy([
              (f) => OrderingTerm(
                  expression: f.dateCreated, mode: OrderingMode.asc)
            ])
            ..limit(1))
          .getSingle();

  Future<void> writeToFolderRevision(
          Insertable<FolderRevision> folderRevision) =>
      (update(folderRevisions)..whereSamePrimaryKey(folderRevision))
          .write(folderRevision);

  SimpleSelectStatement<FileRevisions, FileRevision>
      selectUnconfirmedFileRevisions(String driveId) => select(fileRevisions)
        ..where((r) =>
            r.driveId.equals(driveId) &
            r.metadataTxStatus.equals(TransactionStatus.pending) &
            r.dataTxStatus.equals(TransactionStatus.pending));

  SimpleSelectStatement<FileRevisions, FileRevision> selectFileRevisionsById(
          String driveId, String fileId) =>
      (select(fileRevisions)
        ..where((f) => f.driveId.equals(driveId) & f.fileId.equals(fileId)));

  SimpleSelectStatement<FileRevisions, FileRevision>
      selectLatestFileRevisionsById(String driveId, String fileId) =>
          selectFileRevisionsById(driveId, fileId)
            ..orderBy([
              (f) => OrderingTerm(
                  expression: f.dateCreated, mode: OrderingMode.desc)
            ]);

  Future<FileRevision> getLatestFileRevisionById(
          String driveId, String fileId) =>
      (selectLatestFileRevisionsById(driveId, fileId)..limit(1)).getSingle();

  Future<FileRevision> getOldestFileRevisionById(
          String driveId, String fileId) =>
      (selectFileRevisionsById(driveId, fileId)
            ..orderBy([
              (f) => OrderingTerm(
                  expression: f.dateCreated, mode: OrderingMode.asc)
            ])
            ..limit(1))
          .getSingle();

  Future<void> writeToFileRevision(Insertable<FileRevision> fileRevision) =>
      (update(fileRevisions)..whereSamePrimaryKey(fileRevision))
          .write(fileRevision);
}
