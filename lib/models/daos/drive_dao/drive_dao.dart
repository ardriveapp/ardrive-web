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
part 'drive_order.dart';
part 'folder_node.dart';
part 'folder_with_contents.dart';

@UseDao(include: {
  '../../queries/drive_queries.moor',
  '../../tables/folder_entries.moor',
  '../../tables/folder_revisions.moor',
  '../../tables/file_entries.moor',
  '../../tables/file_revisions.moor'
})
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final _uuid = Uuid();

  DriveDao(Database db) : super(db);

  /// Returns the encryption key for the specified drive.
  ///
  /// `null` if the drive is public and unencrypted.
  Future<SecretKey> getDriveKey(String driveId, SecretKey profileKey) async {
    final drive = await driveById(driveId).getSingle();

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

  Stream<FolderWithContents> watchFolderContents(String driveId,
      {String folderId,
      String folderPath,
      DriveOrder orderBy = DriveOrder.name,
      OrderingMode orderingMode = OrderingMode.asc}) {
    final folderStream = (select(folderEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              (folderId != null
                  ? f.id.equals(folderId)
                  : f.path.equals(folderPath))))
        .watchSingle();

    final subfoldersStream = (select(folderEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              (folderId != null
                  ? f.parentFolderId.equals(folderId)
                  : f.path.like('$folderPath/%') &
                      f.path.like('$folderPath/%/%').not()))
          ..orderBy([
            (f) {
              switch (orderBy) {
                // Folders have no size or proper last updated time to be sorted by
                // so we just sort them ascendingly by name.
                case DriveOrder.lastUpdated:
                case DriveOrder.size:
                  return OrderingTerm(
                      expression: f.name, mode: OrderingMode.asc);
                case DriveOrder.name:
                default:
                  return OrderingTerm(expression: f.name, mode: orderingMode);
              }
            }
          ]))
        .watch();

    final filesStream = (select(fileEntries)
          ..where((f) =>
              f.driveId.equals(driveId) &
              (folderId != null
                  ? f.parentFolderId.equals(folderId)
                  : f.path.like('$folderPath/%') &
                      f.path.like('$folderPath/%/%').not()))
          ..orderBy([
            (f) {
              switch (orderBy) {
                case DriveOrder.lastUpdated:
                  return OrderingTerm(
                      expression: f.lastUpdated, mode: orderingMode);
                case DriveOrder.size:
                  return OrderingTerm(expression: f.size, mode: orderingMode);
                case DriveOrder.name:
                default:
                  return OrderingTerm(expression: f.name, mode: orderingMode);
              }
            }
          ]))
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
    final rootFolder = await folderById(driveId, rootFolderId).getSingle();

    Future<FolderNode> getFolderChildren(FolderEntry parentFolder) async {
      final subfolders =
          await foldersWithParentFolder(driveId, parentFolder.id).get();

      return FolderNode(
        folder: parentFolder,
        // Get the children of this folder's subfolders.
        subfolders:
            await Future.wait(subfolders.map((f) => getFolderChildren(f))),
        files: {
          await for (var f in filesWithParentFolder(driveId, parentFolder.id)
              .get()
              .asStream()
              .expand((f) => f))
            f.id: f.name
        },
      );
    }

    return getFolderChildren(rootFolder);
  }

  SimpleSelectStatement<FileEntries, FileEntry> selectFileInFolderByName(
          String driveId, String folderId, String fileName) =>
      (select(fileEntries)
        ..where((f) =>
            f.driveId.equals(driveId) &
            f.parentFolderId.equals(folderId) &
            f.name.equals(fileName)));

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

  Future<void> writeToFileRevision(Insertable<FileRevision> fileRevision) =>
      (update(fileRevisions)..whereSamePrimaryKey(fileRevision))
          .write(fileRevision);
}
