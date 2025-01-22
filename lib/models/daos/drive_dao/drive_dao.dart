import 'dart:async';
import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/daos/drive_dao/exception.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/search/search_result.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:rxdart/rxdart.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_memory/stash_memory.dart';
import 'package:uuid/uuid.dart';

import '../../../utils/compare_alphabetically_and_natural.dart';

part 'create_drive_result.dart';
part 'drive_dao.g.dart';
part 'drive_order.dart';
part 'folder_node.dart';
part 'folder_with_contents.dart';

@DriftAccessor(include: {'../../queries/drive_queries.drift'})
class DriveDao extends DatabaseAccessor<Database> with _$DriveDaoMixin {
  final _uuid = const Uuid();

  late Vault<SecretKey> _driveKeyVault;

  late Vault<Uint8List> _previewVault;

  final ArDriveCrypto _crypto = ArDriveCrypto();

  DriveDao(
    super.db,
  ) {
    initVaults();
  }

  initVaults() async {
    // Creates a store
    final store = await newMemoryVaultStore();

    // Creates a vault from the previously created store
    _driveKeyVault = await store.vault<SecretKey>(name: 'driveKeyVault');
    _previewVault = await store.vault<Uint8List>(name: 'previewVault');
  }

  Future<void> deleteSharedPrivateDrives(String? owner) async {
    try {
      final drives = (await allDrives().get()).where(
        (drive) =>
            drive.ownerAddress != owner &&
            drive.privacy == DrivePrivacyTag.private,
      );
      for (var drive in drives) {
        await detachDrive(drive.id);
      }
    } catch (e) {
      logger.e('Error deleting shared private drives', e);
    }
  }

  Future<void> detachDrive(String driveId) async {
    try {
      return db.transaction(() async {
        await deleteDriveById(driveId: driveId);
        await deleteAllDriveRevisionsByDriveId(driveId: driveId);
        await deleteFoldersByDriveId(driveId: driveId);
        await deleteFolderRevisionsByDriveId(driveId: driveId);
        await deleteFilesForDriveId(driveId: driveId);
        await deleteFileRevisionsByDriveId(driveId: driveId);
        await deleteLicensesByDriveId(driveId: driveId);
      });
    } catch (e) {
      throw _handleError('Error detaching drive', e);
    }
  }

  Future<SecretKey?> getDriveKeyFromMemory(DriveID driveID) async {
    try {
      return await _driveKeyVault.get(driveID);
    } catch (e) {
      throw _handleError('Error getting drive key from memory', e);
    }
  }

  Future<void> putDriveKeyInMemory({
    required DriveID driveID,
    required SecretKey driveKey,
  }) async {
    try {
      return await _driveKeyVault.put(driveID, driveKey);
    } catch (e) {
      throw _handleError('Error putting drive key in memory', e);
    }
  }

  Future<Uint8List?> getPreviewDataFromMemory(TxID dataTxId) async {
    try {
      return await _previewVault.get(dataTxId);
    } catch (e) {
      throw _handleError('Error getting preview data from memory', e);
    }
  }

  Future<void> putPreviewDataInMemory({
    required TxID dataTxId,
    required Uint8List bytes,
  }) async {
    try {
      await _previewVault.put(dataTxId, bytes);
    } catch (e) {
      throw _handleError('Error putting preview data in memory', e);
    }
  }

  Future<void> insertNewDriveRevisions(
    List<DriveRevisionsCompanion> revisions,
  ) async {
    try {
      await db.batch((b) async {
        b.insertAllOnConflictUpdate(db.driveRevisions, revisions);
      });
    } catch (e) {
      throw _handleError('Error inserting new drive revisions', e);
    }
  }

  Future<void> insertNewFileRevisions(
    List<FileRevisionsCompanion> revisions,
  ) async {
    try {
      await db.batch((b) async {
        b.insertAllOnConflictUpdate(db.fileRevisions, revisions);
      });
    } catch (e) {
      throw _handleError('Error inserting new file revisions', e);
    }
  }

  Future<void> insertNewFolderRevisions(
    List<FolderRevisionsCompanion> revisions,
  ) async {
    try {
      await db.batch((b) async {
        b.insertAllOnConflictUpdate(db.folderRevisions, revisions);
      });
    } catch (e) {
      throw _handleError('Error inserting new folder revisions', e);
    }
  }

  Future<void> insertNewNetworkTransactions(
    List<NetworkTransactionsCompanion> transactions,
  ) async {
    try {
      await db.batch((b) async {
        b.insertAllOnConflictUpdate(db.networkTransactions, transactions);
      });
    } catch (e) {
      throw _handleError('Error inserting new network transactions', e);
    }
  }

  Future<void> updateFolderEntries(
    List<FolderEntriesCompanion> entries,
  ) async {
    try {
      await db.batch((b) async {
        b.insertAllOnConflictUpdate(db.folderEntries, entries);
      });
    } catch (e) {
      throw _handleError('Error updating folder entries', e);
    }
  }

  Future<void> updateFileEntries(
    List<FileEntriesCompanion> entries,
  ) async {
    try {
      await db.batch((b) async {
        b.insertAllOnConflictUpdate(db.fileEntries, entries);
      });
    } catch (e) {
      throw _handleError('Error updating file entries', e);
    }
  }

  Future<void> updateDrive(
    DrivesCompanion drive,
  ) async {
    try {
      await (db.update(drives)..whereSamePrimaryKey(drive)).write(drive);
    } catch (e) {
      throw _handleError('Error updating drive', e);
    }
  }

  Future<void> runTransaction(
    Future<void> Function() transaction,
  ) async {
    await db.transaction(transaction);
  }

  DriveDAOException _handleError(String description, Object error) {
    logger.i(description);
    return DriveDAOException(message: description, error: error);
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
    // TODO: A DAO object should not be responsible for generating UUIDs.
    final driveId = _uuid.v4();
    final rootFolderId = _uuid.v4();

    var insertDriveOp = DrivesCompanion.insert(
      id: driveId,
      name: name,
      ownerAddress: ownerAddress,
      rootFolderId: rootFolderId,
      privacy: privacy,
    );

    // TODO: A DAO object should not be responsible for deriving keys.
    SecretKey? driveKey;
    switch (privacy) {
      case DrivePrivacyTag.private:
        driveKey = await _crypto.deriveDriveKey(wallet, driveId, password);
        insertDriveOp = await _addDriveKeyToDriveCompanion(
            insertDriveOp, profileKey, driveKey);
        break;
      case DrivePrivacyTag.public:
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
          isHidden: const Value(false),
          // TODO: path is not used in the app, so it's not necessary to set it
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
              isHidden: Value(entity.isHidden ?? false),
            );

            if (entity.privacy == DrivePrivacyTag.private) {
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

    if (entity.privacy == DrivePrivacyTag.private) {
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
      _crypto.secretBoxFromDataWithMacConcatenation(
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
    return _crypto.deriveFileKey(driveKey, fileId);
  }

  Future<void> writeToDrive(Insertable<Drive> drive) =>
      (update(drives)..whereSamePrimaryKey(drive)).write(drive);

  Stream<FolderWithContents> watchFolderContents(
    String driveId, {
    String? folderId,
    DriveOrder orderBy = DriveOrder.name,
    OrderingMode orderingMode = OrderingMode.asc,
  }) {
    if (folderId == null) {
      return driveById(driveId: driveId).watchSingleOrNull().switchMap((drive) {
        if (drive == null) {
          throw DriveNotFoundException(driveId);
        }

        return folderById(folderId: drive.rootFolderId)
            .watchSingleOrNull()
            .switchMap((folder) {
          if (folder == null) {
            throw FolderNotFoundInDriveException(driveId, drive.rootFolderId);
          }
          return watchFolderContents(
            driveId,
            folderId: folder.id,
            orderBy: orderBy,
            orderingMode: orderingMode,
          );
        });
      });
    }

    final folderStream = folderById(folderId: folderId).watchSingleOrNull();

    final subfolderQuery = foldersInFolder(
      driveId: driveId,
      parentFolderId: folderId,
      order: (folderEntries) {
        return enumToFolderOrderByClause(
          folderEntries,
          orderBy,
          orderingMode,
        );
      },
    );

    final filesQuery = filesInFolderWithLicenseAndRevisionTransactions(
      driveId: driveId,
      parentFolderId: folderId,
      order: (fileEntries, _, __, ___) {
        return enumToFileOrderByClause(
          fileEntries,
          orderBy,
          orderingMode,
        );
      },
    );

    return Rx.combineLatest3(
        folderStream.where((folder) => folder != null).map((folder) => folder!),
        subfolderQuery.watch(),
        filesQuery.watch(), (
      FolderEntry folder,
      List<FolderEntry> subfolders,
      List<FileWithLicenseAndLatestRevisionTransactions> files,
    ) {
      /// Implementing natural sort this way because to do it in SQLite
      /// it requires triggers, regex spliiting names and creating index fields
      /// and ordering by that index plus interfacing that with moor
      if (orderBy == DriveOrder.name) {
        subfolders
            .sort((a, b) => compareAlphabeticallyAndNatural(a.name, b.name));
        files.sort((a, b) => compareAlphabeticallyAndNatural(a.name, b.name));
        if (orderingMode == OrderingMode.desc) {
          subfolders = subfolders.reversed.toList();
          files = files.reversed.toList();
        }
      }

      return FolderWithContents(
        folder: folder,
        subfolders: subfolders,
        files: files,
      );
    });
  }

  Future<List<SearchResult>> search({
    required String query,
    required SearchQueryType type,
    int limit = 50,
    int offset = 0,
  }) async {
    final List<SearchResult> results = [];

    // Run queries in parallel for better performance
    await Future.wait([
      // Search drives
      if (type == SearchQueryType.all || type == SearchQueryType.drives)
        searchDrives(
          query: query,
          limit: limit,
          offset: offset,
        ).get().then((drives) {
          results.addAll(
            drives.map((drive) => SearchResult<Drive>(
                  result: drive,
                  drive: drive,
                )),
          );
        }),

      // Search folders
      if (type == SearchQueryType.all || type == SearchQueryType.folders)
        searchFolders(
          query: query,
          limit: limit,
          offset: offset,
        ).get().then((folders) {
          results.addAll(
            folders.map((folder) => SearchResult<FolderEntry>(
                  result: FolderEntry(
                    id: folder.id,
                    driveId: folder.driveId,
                    name: folder.name,
                    parentFolderId: folder.parentFolderId,
                    path: '',
                    dateCreated: DateTime.now(),
                    lastUpdated: DateTime.now(),
                    isGhost: false,
                    isHidden: false,
                  ),
                  parentFolder: folder.parentFolderId != null &&
                          folder.parentFolderId != folder.driveId
                      ? FolderEntry(
                          id: folder.parentFolderId!,
                          name: folder.parentFolderName!,
                          driveId: folder.driveId,
                          path: '', // Path is not used as noted in the code
                          dateCreated: DateTime.now(),
                          lastUpdated: DateTime.now(),
                          isGhost: false,
                          isHidden: false,
                        )
                      : null,
                  drive: Drive(
                    id: folder.driveId,
                    name: folder.driveName,
                    privacy: folder.drivePrivacy,
                    rootFolderId: '', // Not needed for search results
                    ownerAddress: '', // Not needed for search results
                    lastUpdated: DateTime.now(),
                    dateCreated: DateTime.now(),
                    isHidden: false,
                  ),
                )),
          );
        }),

      // Search files
      if (type == SearchQueryType.all || type == SearchQueryType.files)
        searchFiles(
          query: query,
          limit: limit,
          offset: offset,
        ).get().then((files) {
          results.addAll(
            files.map((file) => SearchResult<FileEntry>(
                  result: FileEntry(
                    id: file.id,
                    driveId: file.driveId,
                    name: file.name,
                    parentFolderId: file.parentFolderId,
                    path: '',
                    dateCreated: DateTime.now(),
                    lastUpdated: DateTime.now(),
                    isHidden: false,
                    size: file.size,
                    lastModifiedDate: file.lastModifiedDate,
                    dataTxId: file.dataTxId,
                  ),
                  parentFolder: file.parentFolderId != file.driveId
                      ? FolderEntry(
                          id: file.parentFolderId,
                          name: file.parentFolderName!,
                          driveId: file.driveId,
                          path: '', // Path is not used as noted in the code
                          dateCreated: DateTime.now(),
                          lastUpdated: DateTime.now(),
                          isGhost: false,
                          isHidden: false,
                        )
                      : null,
                  drive: Drive(
                    id: file.driveId,
                    name: file.driveName,
                    privacy: file.drivePrivacy,
                    rootFolderId: '', // Not needed for search results
                    ownerAddress: '', // Not needed for search results
                    isHidden: false,
                    lastUpdated: DateTime.now(),
                    dateCreated: DateTime.now(),
                  ),
                )),
          );
        }),
    ]);

    return results;
  }

  /// Create a new folder entry.
  /// Returns the id of the created folder.
  Future<FolderID> createFolder({
    required DriveID driveId,
    FolderID? parentFolderId,
    FolderID? folderId,
    required String folderName,
  }) async {
    final id = folderId ?? _uuid.v4();
    final folderEntriesCompanion = FolderEntriesCompanion.insert(
      id: id,
      driveId: driveId,
      parentFolderId: Value(parentFolderId),
      name: folderName,
      isHidden: const Value(false),
      // TODO: path is not used in the app, so it's not necessary to set it
      path: '',
    );
    await into(folderEntries).insert(folderEntriesCompanion);

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
    final rootFolder = await folderById(folderId: rootFolderId).getSingle();

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
  ) {
    final companion = FileEntriesCompanion.insert(
      id: entity.id!,
      driveId: entity.driveId!,
      parentFolderId: entity.parentFolderId!,
      name: entity.name!,
      dataTxId: entity.dataTxId!,
      size: entity.size!,
      lastModifiedDate: entity.lastModifiedDate ?? DateTime.now(),
      dataContentType: Value(entity.dataContentType),
      pinnedDataOwnerAddress: Value(entity.pinnedDataOwnerAddress),
      isHidden: Value(entity.isHidden ?? false),
      // TODO: path is not used in the app, so it's not necessary to set it
      path: '',
      thumbnail: entity.thumbnail != null
          ? Value(jsonEncode(entity.thumbnail!.toJson()))
          : const Value(null),
      assignedNames: Value(_encodeAssignedNames(entity.assignedNames)),
      fallbackTxId: Value(entity.fallbackTxId),
    );

    return into(fileEntries).insert(
      companion,
      onConflict: DoUpdate((_) => companion.copyWith(dateCreated: null)),
    );
  }

  String? _encodeAssignedNames(List<String>? assignedNames) {
    if (assignedNames == null || assignedNames.isEmpty) {
      return null;
    }
    final namesMap = {'assignedNames': assignedNames};
    return jsonEncode(namesMap);
  }

  Future<void> writeToTransaction(Insertable<NetworkTransaction> transaction) =>
      into(networkTransactions).insertOnConflictUpdate(transaction);

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

  Future<void> insertLicense(
    LicensesCompanion license,
  ) async {
    await db.transaction(() async {
      await Future.wait(
          license.getTransactionCompanions().map((tx) => writeTransaction(tx)));
      await into(licenses).insert(license);
    });
  }

  Future<void> writeTransaction(Insertable<NetworkTransaction> transaction) =>
      into(networkTransactions).insertOnConflictUpdate(transaction);

  Future<void> deleteDrivesAndItsChildren() async {
    await db.transaction(() async {
      await delete(drives).go();
      await delete(fileEntries).go();
      await delete(folderEntries).go();
      await delete(fileRevisions).go();
      await delete(folderRevisions).go();
      await delete(driveRevisions).go();
      await delete(networkTransactions).go();
    });
  }

  Future<int> numberOfFiles() {
    return (select(fileEntries).table.count()).getSingle();
  }

  Future<int> numberOfFolders() {
    return (select(folderEntries).table.count()).getSingle();
  }

  Future<bool> userHasHiddenItems() {
    return hasHiddenItems().getSingle();
  }
}

class FolderNotFoundInDriveException implements Exception {
  final String driveId;
  final String folderId;

  FolderNotFoundInDriveException(this.driveId, this.folderId);

  @override
  String toString() {
    return 'Folder with id $folderId not found in drive with id $driveId';
  }
}

class DriveNotFoundException implements Exception {
  final String driveId;

  DriveNotFoundException(this.driveId);

  @override
  String toString() {
    return 'Drive with id $driveId not found';
  }
}
