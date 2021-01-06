import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import '../../database/database.dart';

part 'create_drive_result.dart';
part 'drive_dao.g.dart';
part 'drive_order.dart';
part 'folder_node.dart';
part 'folder_with_contents.dart';

@UseDao(include: {
  '../../queries/drive_queries.moor',
})
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final _uuid = Uuid();

  DriveDao(Database db) : super(db);

  /// Creates a drive with its accompanying root folder.
  Future<CreateDriveResult> createDrive({
    @required String name,
    @required String ownerAddress,
    @required String privacy,
    Wallet wallet,
    String password,
    SecretKey profileKey,
  }) async {
    final driveId = _uuid.v4();
    final rootFolderId = _uuid.v4();

    var insertDriveOp = DrivesCompanion.insert(
      id: driveId,
      name: name,
      ownerAddress: ownerAddress,
      rootFolderId: rootFolderId,
      privacy: privacy,
    );

    SecretKey driveKey;
    if (privacy == DrivePrivacy.private) {
      driveKey = await deriveDriveKey(wallet, driveId, password);
      insertDriveOp = await _addDriveKeyToDriveCompanion(
          insertDriveOp, profileKey, driveKey);
    }

    await batch((batch) {
      batch.insert(drives, insertDriveOp);

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

    return CreateDriveResult(
      driveId,
      rootFolderId,
      driveKey,
    );
  }

  /// Adds or updates the user's drives with the provided drive entities.
  Future<void> updateUserDrives(
          Map<DriveEntity, SecretKey> driveEntities, SecretKey profileKey) =>
      db.batch((b) async {
        for (final entry in driveEntities.entries) {
          final entity = entry.key;

          var driveCompanion = DrivesCompanion.insert(
            id: entity.id,
            name: entity.name,
            ownerAddress: entity.ownerAddress,
            rootFolderId: entity.rootFolderId,
            privacy: entity.privacy,
            dateCreated: Value(entity.commitTime),
            lastUpdated: Value(entity.commitTime),
          );

          if (entity.privacy == DrivePrivacy.private) {
            driveCompanion = await _addDriveKeyToDriveCompanion(
                driveCompanion, profileKey, entry.value);
          }

          b.insert(
            drives,
            driveCompanion,
            onConflict:
                DoUpdate((_) => driveCompanion.copyWith(dateCreated: null)),
          );
        }
      });

  Future<void> writeDriveEntity({
    String name,
    DriveEntity entity,
  }) {
    assert(entity.privacy == DrivePrivacy.public);

    final companion = DrivesCompanion.insert(
      id: entity.id,
      name: name,
      ownerAddress: entity.ownerAddress,
      rootFolderId: entity.rootFolderId,
      privacy: entity.privacy,
      dateCreated: Value(entity.commitTime),
      lastUpdated: Value(entity.commitTime),
    );

    return into(drives).insert(
      companion,
      onConflict: DoUpdate((_) => companion.copyWith(dateCreated: null)),
    );
  }

  Future<DrivesCompanion> _addDriveKeyToDriveCompanion(
    DrivesCompanion drive,
    SecretKey profileKey,
    SecretKey driveKey,
  ) async {
    final iv = Nonce.randomBytes(96 ~/ 8);
    final encryptedWallet = await aesGcm.encrypt(
      await driveKey.extract(),
      secretKey: profileKey,
      nonce: iv,
    );

    return drive.copyWith(
      encryptedKey: Value(encryptedWallet),
      keyEncryptionIv: Value(iv.bytes),
    );
  }

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
      final subfolders = await foldersInFolder(driveId, parentFolder.id).get();

      return FolderNode(
        folder: parentFolder,
        // Get the children of this folder's subfolders.
        subfolders:
            await Future.wait(subfolders.map((f) => getFolderChildren(f))),
        files: {
          await for (var f in filesInFolder(driveId, parentFolder.id)
              .get()
              .asStream()
              .expand((f) => f))
            f.id: f.name
        },
      );
    }

    return getFolderChildren(rootFolder);
  }

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

  Future<void> writeToTransactions(
          Insertable<NetworkTransaction> transaction) =>
      (update(networkTransactions)..whereSamePrimaryKey(transaction))
          .write(transaction);
}
