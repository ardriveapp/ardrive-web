import 'dart:async';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:moor/moor.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_memory/stash_memory.dart';
import 'package:uuid/uuid.dart';

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

  late Vault<SecretKey> _driveKeyVault;

  DriveDao(Database db) : super(db) {
    // Creates a store
    final store = newMemoryVaultStore();

    // Creates a vault from the previously created store
    _driveKeyVault = store.vault<SecretKey>(name: 'driveKeyVault');
  }

  Future<void> deleteSharedPrivateDrives(String? owner) async {
    final drives = (await allDrives().get()).where(
      (drive) =>
          drive.ownerAddress != owner && drive.privacy == DrivePrivacy.private,
    );
    drives.forEach((drive) async {
      await detachDrive(drive.id);
    });
  }

  Future<void> detachDrive(String driveId) async {
    return db.transaction(() async {
      await deleteDriveById(driveId: driveId);
      await deleteAllDriveRevisionsByDriveId(driveId: driveId);
      await deleteFoldersByDriveId(driveId: driveId);
      await deleteFolderRevisionsByDriveId(driveId: driveId);
      await deleteFilesForDriveId(driveId: driveId);
      await deleteFileRevisionsByDriveId(driveId: driveId);
    });
  }

  Future<SecretKey?> getDriveKeyFromMemory(DriveID driveID) async {
    return await _driveKeyVault.get(driveID);
  }

  Future<void> putDriveKeyInMemory({
    required DriveID driveID,
    required SecretKey driveKey,
  }) async {
    return await _driveKeyVault.put(driveID, driveKey);
  }

  /// Creates a drive with its accompanying root folder.
  Future<CreateDriveResult> createDrive({
    required String name,
    required String ownerAddress,
    required String privacy,
    required Wallet wallet,
    required String password,
    required SecretKey profileKey,
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

    SecretKey? driveKey;
    switch (privacy) {
      case DrivePrivacy.private:
        driveKey = await deriveDriveKey(wallet, driveId, password);
        insertDriveOp = await _addDriveKeyToDriveCompanion(
            insertDriveOp, profileKey, driveKey);
        break;
      case DrivePrivacy.public:
        // Nothing to do
        break;
    }

    await batch((batch) {
      batch.insert(drives, insertDriveOp);

      batch.insert(
        folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: name,
          path: rootPath,
        ),
      );
    });

    return CreateDriveResult(
      driveId,
      rootFolderId,
      driveKey,
    );
  }

  Future<bool> doesEntityWithNameExist({
    required String name,
    required DriveID driveId,
    required FolderID parentFolderId,
  }) async {
    final foldersWithName = await foldersInFolderWithName(
      driveId: driveId,
      parentFolderId: parentFolderId,
      name: name,
    ).get();

    final filesWithName = await filesInFolderWithName(
      driveId: driveId,
      parentFolderId: parentFolderId,
      name: name,
    ).get();

    return foldersWithName.isNotEmpty || filesWithName.isNotEmpty;
  }

  /// Adds or updates the user's drives with the provided drive entities.
  Future<void> updateUserDrives(
    Map<DriveEntity, SecretKey?> driveEntities,
    SecretKey? profileKey,
  ) =>
      db.batch(
        (b) async {
          for (final entry in driveEntities.entries) {
            final entity = entry.key;

            var driveCompanion = DrivesCompanion.insert(
              id: entity.id!,
              name: entity.name!,
              ownerAddress: entity.ownerAddress,
              rootFolderId: entity.rootFolderId!,
              privacy: entity.privacy!,
              dateCreated: Value(entity.createdAt),
              lastUpdated: Value(entity.createdAt),
            );

            if (entity.privacy == DrivePrivacy.private) {
              driveCompanion = await _addDriveKeyToDriveCompanion(
                  driveCompanion, profileKey!, entry.value!);
            }

            b.insert(
              drives,
              driveCompanion,
              onConflict: DoUpdate(
                  (dynamic _) => driveCompanion.copyWith(dateCreated: null)),
            );
          }
        },
      );

  Future<void> writeDriveEntity({
    required String name,
    required DriveEntity entity,
    SecretKey? driveKey,
    SecretKey? profileKey,
  }) async {
    var companion = DrivesCompanion.insert(
      id: entity.id!,
      name: name,
      ownerAddress: entity.ownerAddress,
      rootFolderId: entity.rootFolderId!,
      privacy: entity.privacy!,
      dateCreated: Value(entity.createdAt),
      lastUpdated: Value(entity.createdAt),
    );

    if (entity.privacy == DrivePrivacy.private) {
      if (profileKey != null) {
        companion = await _addDriveKeyToDriveCompanion(
          companion,
          profileKey,
          driveKey!,
        );
      } else {
        await putDriveKeyInMemory(
          driveID: entity.id!,
          driveKey: driveKey!,
        );
      }
    }

    await into(drives).insert(
      companion,
      onConflict: DoUpdate((_) => companion.copyWith(dateCreated: null)),
    );
  }

  Future<DrivesCompanion> _addDriveKeyToDriveCompanion(
    DrivesCompanion drive,
    SecretKey profileKey,
    SecretKey driveKey,
  ) async {
    final encryptionRes = await aesGcm.encrypt(
      await driveKey.extractBytes(),
      secretKey: profileKey,
    );

    return drive.copyWith(
      encryptedKey: Value(encryptionRes.concatenation(nonce: false)),
      keyEncryptionIv: Value(encryptionRes.nonce as Uint8List),
    );
  }

  /// Returns the encryption key for the specified drive.
  ///
  /// `null` if the drive is public and unencrypted.
  Future<SecretKey?> getDriveKey(String driveId, SecretKey profileKey) async {
    final drive = await driveById(driveId: driveId).getSingle();

    if (drive.encryptedKey == null) {
      return null;
    }

    final driveKeyData = await aesGcm.decrypt(
      secretBoxFromDataWithMacConcatenation(
        drive.encryptedKey!,
        nonce: drive.keyEncryptionIv!,
      ),
      secretKey: profileKey,
    );

    return SecretKey(driveKeyData);
  }

  /// Returns the encryption key for the specified file.
  ///
  /// `null` if the file is public and unencrypted.
  Future<SecretKey> getFileKey(
    String fileId,
    SecretKey driveKey,
  ) async {
    return deriveFileKey(driveKey, fileId);
  }

  Future<void> writeToDrive(Insertable<Drive> drive) =>
      (update(drives)..whereSamePrimaryKey(drive)).write(drive);

  Stream<FolderWithContents> watchFolderContents(
    String driveId, {
    String? folderId,
    String? folderPath,
    DriveOrder orderBy = DriveOrder.name,
    OrderingMode orderingMode = OrderingMode.asc,
  }) {
    assert(folderId != null || folderPath != null);
    final folderStream = (folderId != null
            ? folderById(driveId: driveId, folderId: folderId)
            : folderWithPath(driveId: driveId, path: folderPath!))
        .watchSingleOrNull();
    final subfolderOrder =
        enumToFolderOrderByClause(folderEntries, orderBy, orderingMode);

    final subfolderQuery = (folderId != null
        ? foldersInFolder(
            driveId: driveId, parentFolderId: folderId, order: subfolderOrder)
        : foldersInFolderAtPath(
            driveId: driveId, path: folderPath!, order: subfolderOrder));

    final filesOrder =
        enumToFileOrderByClause(fileEntries, orderBy, orderingMode);

    final filesQuery = folderId != null
        ? filesInFolderWithRevisionTransactions(
            driveId: driveId, parentFolderId: folderId, order: filesOrder)
        : filesInFolderAtPathWithRevisionTransactions(
            driveId: driveId, path: folderPath!, order: filesOrder);

    return Rx.combineLatest3(
      folderStream.where((folder) => folder != null).map((folder) => folder!),
      subfolderQuery.watch(),
      filesQuery.watch(),
      (
        FolderEntry folder,
        List<FolderEntry> subfolders,
        List<FileWithLatestRevisionTransactions> files,
      ) =>
          FolderWithContents(
        folder: folder,
        subfolders: subfolders,
        files: files,
      ),
    );
  }

  /// Create a new folder entry.
  /// Returns the id of the created folder.
  Future<FolderEntriesCompanion> createFolder({
    required String driveId,
    String? parentFolderId,
    String? folderId,
    required String folderName,
    required String path,
  }) async {
    final id = folderId ?? _uuid.v4();
    final folderEntriesCompanion = FolderEntriesCompanion.insert(
      id: id,
      driveId: driveId,
      parentFolderId: Value(parentFolderId),
      name: folderName,
      path: path,
    );
    await into(folderEntries).insert(folderEntriesCompanion);

    return folderEntriesCompanion;
  }

  UpdateStatement<FolderEntries, FolderEntry> updateFolderById(
          String driveId, String folderId) =>
      update(folderEntries)
        ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId));

  Future<void> writeToFolder(Insertable<FolderEntry> folder) =>
      (update(folderEntries)..whereSamePrimaryKey(folder)).write(folder);

  /// Constructs a tree of folders and files that are children of the specified folder.
  Future<FolderNode> getFolderTree(String driveId, String rootFolderId) async {
    final rootFolder =
        await folderById(driveId: driveId, folderId: rootFolderId).getSingle();

    Future<FolderNode> getFolderChildren(FolderEntry parentFolder) async {
      final subfolders = await foldersInFolder(
              driveId: driveId, parentFolderId: parentFolder.id)
          .get();

      return FolderNode(
        folder: parentFolder,
        // Get the children of this folder's subfolders.
        subfolders:
            await Future.wait(subfolders.map((f) => getFolderChildren(f))),
        files: {
          await for (var f in filesInFolder(
                  driveId: driveId, parentFolderId: parentFolder.id)
              .get()
              .asStream()
              .expand((f) => f))
            f.id: f
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
      id: entity.id!,
      driveId: entity.driveId!,
      parentFolderId: entity.parentFolderId!,
      name: entity.name!,
      path: path,
      dataTxId: entity.dataTxId!,
      size: entity.size!,
      lastModifiedDate: entity.lastModifiedDate ?? DateTime.now(),
      dataContentType: Value(entity.dataContentType),
    );

    return into(fileEntries).insert(
      companion,
      onConflict: DoUpdate((_) => companion.copyWith(dateCreated: null)),
    );
  }

  Future<void> writeToTransaction(Insertable<NetworkTransaction> transaction) =>
      (update(networkTransactions)..whereSamePrimaryKey(transaction))
          .write(transaction);

  Future<void> insertDriveRevision(DriveRevisionsCompanion revision) async {
    await db.transaction(() async {
      await writeTransaction(revision.getTransactionCompanion());
      await into(driveRevisions).insert(revision);
    });
  }

  Future<void> insertFolderRevision(FolderRevisionsCompanion revision) async {
    await db.transaction(() async {
      await writeTransaction(revision.getTransactionCompanion());
      await into(folderRevisions).insert(revision);
    });
  }

  /// Inserts the specified file revision and its associated metadata and data transactions.
  Future<void> insertFileRevision(FileRevisionsCompanion revision) async {
    await db.transaction(() async {
      await Future.wait(revision
          .getTransactionCompanions()
          .map((tx) => writeTransaction(tx)));
      await into(fileRevisions).insert(revision);
    });
  }

  Future<void> writeTransaction(Insertable<NetworkTransaction> transaction) =>
      into(networkTransactions).insertOnConflictUpdate(transaction);
}
