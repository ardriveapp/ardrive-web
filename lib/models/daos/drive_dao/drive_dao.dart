import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:ardrive/utils/snapshots/misdecoded_text.dart';
import 'package:ardrive/utils/preview_byte_cache.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
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

  late Vault<DriveKey> _driveKeyVault;

  /// Completes once [_driveKeyVault] exists. Every use of the vault waits for
  /// it: the constructor cannot await, and a drive key stored in the moment
  /// after start-up used to reach for a vault that was not there yet.
  late final Future<void> _vaultsReady;

  /// Recently previewed bytes, held to a total size. See [PreviewByteCache].
  final PreviewByteCache _previewCache = PreviewByteCache();

  final ArDriveCrypto _crypto = ArDriveCrypto();

  DriveDao(
    super.db,
  ) {
    _vaultsReady = _initVaults();
  }

  Future<void> _initVaults() async {
    // Creates a store
    final store = await newMemoryVaultStore();

    // Creates a vault from the previously created store
    _driveKeyVault = await store.vault<DriveKey>(name: 'driveKeyVault');
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

  Future<DriveKey?> getDriveKeyFromMemory(DriveID driveID) async {
    try {
      await _vaultsReady;
      return await _driveKeyVault.get(driveID);
    } catch (e) {
      throw _handleError('Error getting drive key from memory', e);
    }
  }

  Future<void> putDriveKeyInMemory({
    required DriveID driveID,
    required DriveKey driveKey,
  }) async {
    try {
      await _vaultsReady;
      return await _driveKeyVault.put(driveID, driveKey);
    } catch (e) {
      throw _handleError('Error putting drive key in memory', e);
    }
  }

  /// Encrypts onto their rows the drive keys that only memory holds.
  ///
  /// A private drive opened without a profile stores its key in the memory
  /// vault alone, because there is no profile key to encrypt it with. Once the
  /// user signs in there is, and the sync reads a signed-in user's keys from
  /// the row and nowhere else ([getDriveKey] deliberately never falls back to
  /// the vault: a private row with no key is how the sync knows it has nothing
  /// to open an artifact with). So this runs before the profile is announced
  /// as logged in, and the drive the visitor just opened keeps working.
  ///
  /// Returns the ids of the drives whose rows were written.
  Future<List<DriveID>> persistInMemoryDriveKeys(SecretKey profileKey) async {
    final written = <DriveID>[];

    try {
      await _vaultsReady;

      final drives = (await allDrives().get()).where(
        (drive) => drive.isPrivate && drive.encryptedKey == null,
      );

      for (final drive in drives) {
        final driveKey = await _driveKeyVault.get(drive.id);

        if (driveKey == null) {
          continue;
        }

        final encryptionRes = await aesGcm.encrypt(
          await driveKey.key.extractBytes(),
          secretKey: profileKey,
        );

        await (update(this.drives)..where((d) => d.id.equals(drive.id))).write(
          DrivesCompanion(
            encryptedKey: Value(encryptionRes.concatenation(nonce: false)),
            driveKeyGenerated: Value(driveKey.generated),
            keyEncryptionIv: Value(encryptionRes.nonce as Uint8List),
          ),
        );

        written.add(drive.id);
      }
    } catch (e) {
      throw _handleError('Error persisting in-memory drive keys', e);
    }

    return written;
  }

  Future<Uint8List?> getPreviewDataFromMemory(TxID dataTxId) async =>
      _previewCache.get(dataTxId);

  /// Which signed-in session the memory belongs to. [clearSessionMemory]
  /// moves it on.
  int _previewSession = 0;

  /// The session a preview fetch starts in, to hand back to
  /// [putPreviewDataInMemory] when its bytes arrive.
  int get previewSession => _previewSession;

  /// Keeps [bytes] for [dataTxId], unless the session they were fetched in
  /// has since ended: a download that finishes after logout must not put the
  /// previous session's bytes back into memory that logout just cleared.
  Future<void> putPreviewDataInMemory({
    required TxID dataTxId,
    required Uint8List bytes,
    required int session,
  }) async {
    if (session != _previewSession) {
      return;
    }

    _previewCache.put(dataTxId, bytes);
  }

  /// Forgets everything this DAO holds in memory for the signed-in session:
  /// drive keys, and the bytes of recently previewed files.
  ///
  /// Logout deletes every table, and used to leave both of these behind until
  /// the tab closed - including the keys to shared private drives opened from
  /// a `driveKey` link, which are kept here rather than in the database.
  Future<void> clearSessionMemory() async {
    _previewSession++;
    _previewCache.clear();

    try {
      await _vaultsReady;
      await _driveKeyVault.clear();
    } catch (e) {
      throw _handleError('Error clearing drive keys from memory', e);
    }
  }

  /// Bulk-loads ALL latest file revisions for a drive into a map keyed by fileId.
  Future<Map<String, FileRevision>> getAllLatestFileRevisionsMap(
      String driveId) async {
    final revisions =
        await allLatestFileRevisionsByDriveId(driveId: driveId).get();
    return {for (final rev in revisions) rev.fileId: rev};
  }

  /// Bulk-loads ALL oldest file revisions for a drive into a map keyed by fileId.
  Future<Map<String, FileRevision>> getAllOldestFileRevisionsMap(
      String driveId) async {
    final revisions =
        await allOldestFileRevisionsByDriveId(driveId: driveId).get();
    return {for (final rev in revisions) rev.fileId: rev};
  }

  /// Bulk-loads ALL latest folder revisions for a drive into a map keyed by folderId.
  Future<Map<String, FolderRevision>> getAllLatestFolderRevisionsMap(
      String driveId) async {
    final revisions =
        await allLatestFolderRevisionsByDriveId(driveId: driveId).get();
    return {for (final rev in revisions) rev.folderId: rev};
  }

  /// Bulk-loads ALL oldest folder revisions for a drive into a map keyed by folderId.
  Future<Map<String, FolderRevision>> getAllOldestFolderRevisionsMap(
      String driveId) async {
    final revisions =
        await allOldestFolderRevisionsByDriveId(driveId: driveId).get();
    return {for (final rev in revisions) rev.folderId: rev};
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
    required String? signatureType,
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
      signatureType: Value.absentIfNull(signatureType),
    );

    // TODO: A DAO object should not be responsible for deriving keys.
    DriveKey? driveKey;
    switch (privacy) {
      case DrivePrivacyTag.private:
        driveKey = await _crypto.deriveDriveKey(
            wallet, driveId, password, DriveSignatureType.v2, null);
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
      driveKey?.key,
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

  /// A stand-in row for a drive's root folder.
  ///
  /// A drive row whose `rootFolderId` has no matching folder row cannot be
  /// opened at all: [watchFolderContents] drops the missing folder with a
  /// `.where` and its combined stream then never emits, stranding the explorer
  /// on a spinner that nothing retries. That happens whenever the root
  /// folder's own metadata transaction fails to resolve during sync while the
  /// drive entity itself resolves fine - and `rootFolderId` is known from the
  /// drive entity either way, so the row can always be written.
  ///
  /// Two deliberate choices:
  ///
  /// * **Insert with [InsertMode.insertOrIgnore].** This must never overwrite a
  ///   real root folder that already synced, and it is re-run on every sync, so
  ///   it also heals drives already in this state rather than only preventing
  ///   new ones.
  /// * **Not marked `isGhost`.** `FolderRevisionCompanionExtensions
  ///   .toEntryCompanion` omits `isGhost`, so the upsert that lands the real
  ///   metadata leaves absent columns untouched and the flag would stick
  ///   forever. `parentFolderId` is left null for the same care: [createGhosts]
  ///   points a ghost at `drive.rootFolderId`, which for the root itself would
  ///   be a self-reference - which is why that method excludes root folders and
  ///   why this is a placeholder rather than a ghost.
  FolderEntriesCompanion _rootFolderPlaceholder({
    required DriveID driveId,
    required FolderID rootFolderId,
    required String name,
  }) =>
      FolderEntriesCompanion.insert(
        id: rootFolderId,
        driveId: driveId,
        name: name,
        isHidden: const Value(false),
        // TODO: path is not used in the app, so it's not necessary to set it
        path: '',
      );

  /// Adds or updates the user's drives with the provided drive entities.
  ///
  /// Each entity is a drive's newest revision, so its time is when the drive
  /// last changed, not when it was made. [creationTimes], keyed by drive id,
  /// says when it was made. A drive missing from it keeps the creation date
  /// it already has, and a new one takes its newest revision's time.
  Future<void> updateUserDrives(
    Map<DriveEntity, DriveKey?> driveEntities,
    SecretKey? profileKey, {
    Map<String, DateTime> creationTimes = const {},
  }) =>
      db.batch(
        (b) async {
          for (final entry in driveEntities.entries) {
            final entity = entry.key;
            final createdAt = creationTimes[entity.id];

            var driveCompanion = DrivesCompanion.insert(
              id: entity.id!,
              name: entity.name!,
              ownerAddress: entity.ownerAddress,
              rootFolderId: entity.rootFolderId!,
              privacy: entity.privacy!,
              dateCreated: Value(createdAt ?? entity.createdAt),
              lastUpdated: Value(entity.createdAt),
              isHidden: Value(entity.isHidden ?? false),
              signatureType: Value.absentIfNull(entity.signatureType?.value),
            );

            if (entity.privacy == DrivePrivacyTag.private) {
              driveCompanion = await _addDriveKeyToDriveCompanion(
                  driveCompanion, profileKey!, entry.value!);
            }

            // `copyWith(dateCreated: null)` kept the value rather than
            // dropping it, so every pass wrote the newest revision's time over
            // the creation date. Absent leaves the stored one alone; a known
            // creation time replaces it, which also repairs a drive that pass
            // got wrong.
            final onConflict = createdAt == null
                ? driveCompanion.copyWith(dateCreated: const Value.absent())
                : driveCompanion;

            b.insert(
              drives,
              driveCompanion,
              onConflict: DoUpdate((dynamic _) => onConflict),
            );

            b.insert(
              folderEntries,
              _rootFolderPlaceholder(
                driveId: entity.id!,
                rootFolderId: entity.rootFolderId!,
                name: entity.name!,
              ),
              mode: InsertMode.insertOrIgnore,
            );
          }
        },
      );

  Future<void> writeDriveEntity({
    required String name,
    required DriveEntity entity,
    DriveKey? driveKey,
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
      signatureType: Value.absentIfNull(entity.signatureType?.value),
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

    // One transaction so the drive and its root folder land together. Written
    // separately, a stream observer could catch the gap between them and see
    // exactly the drive-without-a-root-folder state this placeholder exists to
    // rule out. `updateUserDrives` gets this for free from `db.batch`.
    await db.transaction(() async {
      // Absent, not null: `copyWith(dateCreated: null)` keeps the value, and
      // [entity] is the drive's newest revision, so a re-attach wrote the
      // rename's date over the creation date.
      await into(drives).insert(
        companion,
        onConflict: DoUpdate(
          (_) => companion.copyWith(dateCreated: const Value.absent()),
        ),
      );

      await into(folderEntries).insert(
        _rootFolderPlaceholder(
          driveId: entity.id!,
          rootFolderId: entity.rootFolderId!,
          name: name,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    });
  }

  /// Seeds the drive a library page (`LibraryMode`) imports into: its row
  /// and its root folder placeholder, in one transaction as
  /// [writeDriveEntity] writes them.
  ///
  /// The importer refuses to import into a drive this client has no row for,
  /// and a library page has never synced. `lastUpdated` is the epoch so that
  /// the drive metadata in the snapshot, whatever its date, always wins.
  Future<void> writeLibraryDrive({
    required DriveID driveId,
    required FolderID rootFolderId,
    required String ownerAddress,
    required String privacy,
    required String name,
  }) =>
      db.transaction(() async {
        await into(drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: name,
            ownerAddress: ownerAddress,
            rootFolderId: rootFolderId,
            privacy: privacy,
            lastUpdated: Value(DateTime.fromMillisecondsSinceEpoch(0)),
          ),
          mode: InsertMode.insertOrReplace,
        );
        await into(folderEntries).insert(
          _rootFolderPlaceholder(
            driveId: driveId,
            rootFolderId: rootFolderId,
            name: name,
          ),
          mode: InsertMode.insertOrIgnore,
        );
      });

  Future<DrivesCompanion> _addDriveKeyToDriveCompanion(
    DrivesCompanion drive,
    SecretKey profileKey,
    DriveKey driveKey,
  ) async {
    final encryptionRes = await aesGcm.encrypt(
      await driveKey.key.extractBytes(),
      secretKey: profileKey,
    );

    return drive.copyWith(
      encryptedKey: Value(encryptionRes.concatenation(nonce: false)),
      driveKeyGenerated: Value(driveKey.generated),
      keyEncryptionIv: Value(encryptionRes.nonce as Uint8List),
    );
  }

  /// Returns the encryption key for the specified drive.
  ///
  /// `null` if the drive is public and unencrypted.
  Future<DriveKey?> getDriveKey(String driveId, SecretKey profileKey) async {
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

    return DriveKey(SecretKey(driveKeyData), drive.driveKeyGenerated!);
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
    // Run queries in parallel for better performance. The results are put
    // together in a fixed order afterwards: appended as each query finished,
    // their order changed from one search to the next.
    final drivesSearch =
        type == SearchQueryType.all || type == SearchQueryType.drives
            ? searchDrives(query: query, limit: limit, offset: offset).get()
            : Future.value(<Drive>[]);
    final foldersSearch =
        type == SearchQueryType.all || type == SearchQueryType.folders
            ? searchFolders(query: query, limit: limit, offset: offset).get()
            : Future.value(<FolderSearchResult>[]);
    final filesSearch =
        type == SearchQueryType.all || type == SearchQueryType.files
            ? searchFiles(query: query, limit: limit, offset: offset).get()
            : Future.value(<FileSearchResult>[]);

    final drives = await drivesSearch;
    final folders = await foldersSearch;
    final files = await filesSearch;

    return [
      ...drives.map((drive) => SearchResult<Drive>(
            result: drive,
            drive: drive,
          )),
      ...folders.map((folder) => SearchResult<FolderEntry>(
            result: FolderEntry(
              id: folder.id,
              driveId: folder.driveId,
              name: folder.name,
              parentFolderId: folder.parentFolderId,
              path: '',
              dateCreated: DateTime.now(),
              lastUpdated: DateTime.now(),
              isGhost: false,
              isHidden: folder.isHidden,
            ),
            parentFolder: _searchResultParent(
              driveId: folder.driveId,
              parentFolderId: folder.parentFolderId,
              parentFolderName: folder.parentFolderName,
              driveRootFolderId: folder.driveRootFolderId,
            ),
            drive: Drive(
              id: folder.driveId,
              name: folder.driveName,
              privacy: folder.drivePrivacy,
              rootFolderId: folder.driveRootFolderId,
              ownerAddress: '', // Not needed for search results
              lastUpdated: DateTime.now(),
              dateCreated: DateTime.now(),
              isHidden: folder.driveIsHidden,
            ),
          )),
      ...files.map((file) => SearchResult<FileEntry>(
            result: FileEntry(
              id: file.id,
              driveId: file.driveId,
              name: file.name,
              parentFolderId: file.parentFolderId,
              path: '',
              dateCreated: DateTime.now(),
              lastUpdated: DateTime.now(),
              isHidden: file.isHidden,
              size: file.size,
              lastModifiedDate: file.lastModifiedDate,
              dataTxId: file.dataTxId,
              dataContentType: file.dataContentType,
            ),
            parentFolder: _searchResultParent(
              driveId: file.driveId,
              parentFolderId: file.parentFolderId,
              parentFolderName: file.parentFolderName,
              driveRootFolderId: file.driveRootFolderId,
            ),
            drive: Drive(
              id: file.driveId,
              name: file.driveName,
              privacy: file.drivePrivacy,
              rootFolderId: file.driveRootFolderId,
              ownerAddress: '', // Not needed for search results
              isHidden: file.driveIsHidden,
              lastUpdated: DateTime.now(),
              dateCreated: DateTime.now(),
            ),
          )),
    ];
  }

  /// The folder a search result sits in, or null when that is the drive's
  /// root, which a result names by its drive instead.
  ///
  /// The root used to be told apart by comparing the folder id with the drive
  /// id, which never match, so an item at the top of a drive was listed as in
  /// a folder named after the drive (the root folder's own name). Null too
  /// when the parent folder is not on this device: the join finds no name, and
  /// it was read with `!`, which threw and failed the whole search.
  FolderEntry? _searchResultParent({
    required String driveId,
    required String? parentFolderId,
    required String? parentFolderName,
    required String driveRootFolderId,
  }) {
    if (parentFolderId == null ||
        parentFolderId == driveRootFolderId ||
        parentFolderName == null) {
      return null;
    }

    return FolderEntry(
      id: parentFolderId,
      name: parentFolderName,
      driveId: driveId,
      path: '', // Path is not used as noted in the code
      dateCreated: DateTime.now(),
      lastUpdated: DateTime.now(),
      isGhost: false,
      isHidden: false,
    );
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
  /// The folder tree under [rootFolderId], with every file in it.
  ///
  /// Two queries for the whole drive, grouped by parent here, rather than two
  /// per folder: on the web the database runs in a worker and every query is
  /// a round trip (docs/WEB_DATABASE.md). Both read in the order the
  /// per-folder queries did, a scan of the table, so each folder's children
  /// come out in the same order as before.
  Future<FolderNode> getFolderTree(String driveId, String rootFolderId) async {
    final rootFolder = await folderById(folderId: rootFolderId).getSingle();

    final subfoldersByParent = <String, List<FolderEntry>>{};
    for (final folder in await (select(folderEntries)
          ..where((f) => f.driveId.equals(driveId)))
        .get()) {
      final parent = folder.parentFolderId;
      if (parent == null) continue;
      (subfoldersByParent[parent] ??= []).add(folder);
    }
    final filesByParent = <String, List<FileEntry>>{};
    for (final file in await (select(fileEntries)
          ..where((f) => f.driveId.equals(driveId)))
        .get()) {
      (filesByParent[file.parentFolderId] ??= []).add(file);
    }

    // A folder already on the path is not entered again: a cycle in the
    // rows, which no sync or import writes, would otherwise recurse for ever.
    FolderNode build(FolderEntry folder, Set<String> path) {
      final onPath = {...path, folder.id};
      return FolderNode(
        folder: folder,
        subfolders: [
          for (final child in subfoldersByParent[folder.id] ?? <FolderEntry>[])
            if (!onPath.contains(child.id)) build(child, onPath),
        ],
        files: {
          for (final file in filesByParent[folder.id] ?? <FileEntry>[])
            file.id: file,
        },
      );
    }

    return build(rootFolder, const {});
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
      // The time of the revision written with it, as a sync records it. Left
      // to the column's default, it was set on insert and never again, so a
      // new version uploaded here kept the first version's date until the
      // next sync.
      lastUpdated: Value(entity.createdAt),
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

  /// Whether this drive has anything in it on this device: a file, or a
  /// folder other than its root.
  ///
  /// Asked of the drive, not of a folder, so the answer is the same from the
  /// list of drives as from inside an empty subfolder of a full drive.
  Future<bool> driveHasEntries({
    required String driveId,
    required String rootFolderId,
  }) async {
    final file = await (selectOnly(fileEntries)
          ..addColumns([fileEntries.id])
          ..where(fileEntries.driveId.equals(driveId))
          ..limit(1))
        .getSingleOrNull();
    if (file != null) {
      return true;
    }

    final folder = await (selectOnly(folderEntries)
          ..addColumns([folderEntries.id])
          ..where(folderEntries.driveId.equals(driveId) &
              folderEntries.id.equals(rootFolderId).not())
          ..limit(1))
        .getSingleOrNull();
    return folder != null;
  }

  Future<bool> userHasHiddenItems() {
    return hasHiddenItems().getSingle();
  }

  /// How much of each drive is actually on this device, in one pass.
  ///
  /// Grouped rather than asked per drive: the drives list wants both numbers
  /// for every drive at once, and a wallet with thirty drives should cost one
  /// query rather than sixty. A drive with no local file rows is simply absent
  /// from the map - there is no row to group - which the caller reads as zero.
  ///
  /// Both numbers describe the local database and nothing else. A drive that
  /// has never been walked has no rows, so its size reads as zero bytes rather
  /// than as the truth, which is that we do not know. That is why
  /// [DriveContentSummary.totalSize] is only ever published for a drive whose
  /// history has actually been walked - see `DriveListItem.size`.
  Future<Map<String, DriveContentSummary>> driveContentSummaries() async {
    final fileCount = fileEntries.id.count();
    final totalSize = fileEntries.size.sum();

    final query = selectOnly(fileEntries)
      ..addColumns([fileEntries.driveId, fileCount, totalSize])
      ..groupBy([fileEntries.driveId]);

    final rows = await query.get();

    return {
      for (final row in rows)
        row.read(fileEntries.driveId)!: DriveContentSummary(
          fileCount: row.read(fileCount) ?? 0,
          totalSize: row.read(totalSize) ?? 0,
        ),
    };
  }

  /// What [driveIds] hold permanently, by the year it was uploaded, oldest
  /// first.
  ///
  /// Stricter than [driveContentSummaries], which counts every file row,
  /// because this is a figure somebody may hold us to:
  ///
  /// - **Every version.** Read from the revisions, not the files: a file's
  ///   earlier versions are stored, and were paid for, as much as its
  ///   newest.
  /// - **Each piece of data once.** A file copied to a second folder, or
  ///   renamed, is another revision over the same data transaction, stored
  ///   once and paid for once.
  /// - **Only data that landed.** An upload still pending, or one that
  ///   failed, is not preserved. Data with no transaction row at all was
  ///   synced from the network, so it is there.
  /// - **Not pinned files.** A pin points at somebody else's data, which
  ///   they paid to store.
  ///
  /// A piece of data is dated by the first revision that carried it: when
  /// it was uploaded, not when its file was first made.
  Future<Map<int, PermanentData>> permanentDataByYear(
    Iterable<String> driveIds,
  ) async {
    final ids = driveIds.toList();

    if (ids.isEmpty) {
      return {};
    }

    final rows = await customSelect(
      '''
      SELECT CAST(strftime('%Y', created, 'unixepoch') AS INTEGER) AS year,
             SUM(size) AS bytes,
             COUNT(*) AS items
      FROM (
        SELECT r.dataTxId, MIN(r.dateCreated) AS created, MAX(r.size) AS size
        FROM file_revisions r
        WHERE ${_permanentRevisions(ids)}
        GROUP BY r.dataTxId
      )
      GROUP BY year
      ORDER BY year
      ''',
      variables: [for (final id in ids) Variable.withString(id)],
      readsFrom: {fileRevisions, networkTransactions},
    ).get();

    return {
      for (final row in rows)
        if (row.read<int?>('year') != null)
          row.read<int>('year'): PermanentData(
            bytes: row.read<int?>('bytes') ?? 0,
            items: row.read<int>('items'),
          ),
    };
  }

  /// How many files in [driveIds] have at least one version stored for
  /// good, counted as [permanentDataByYear] counts their data. A copy is a
  /// file of its own here, though its data is counted once there.
  Future<int> permanentFileCount(Iterable<String> driveIds) async {
    final ids = driveIds.toList();

    if (ids.isEmpty) {
      return 0;
    }

    final row = await customSelect(
      '''
      SELECT COUNT(DISTINCT r.fileId) AS files
      FROM file_revisions r
      WHERE ${_permanentRevisions(ids)}
      ''',
      variables: [for (final id in ids) Variable.withString(id)],
      readsFrom: {fileRevisions, networkTransactions},
    ).getSingle();

    return row.read<int>('files');
  }

  /// Changes whenever [permanentDataByYear] or [permanentFileCount] could:
  /// when a revision is written, or an upload starts, lands or fails. For
  /// deciding whether figures already counted still hold, at a fraction of a
  /// millisecond against a scan of every revision.
  ///
  /// Revisions are only ever added, so the newest row's id moves with every
  /// one written. An upload that lands leaves the pending count; one that
  /// fails moves to the failed count.
  Future<String> permanentDataVersion() async {
    final row = await customSelect(
      '''
      SELECT (SELECT MAX(rowid) FROM file_revisions) AS revisions,
             (SELECT COUNT(*) FROM network_transactions
               WHERE status = '${TransactionStatus.pending}') AS pending,
             (SELECT COUNT(*) FROM network_transactions
               WHERE status = '${TransactionStatus.failed}') AS failed
      ''',
      readsFrom: {fileRevisions, networkTransactions},
    ).getSingle();

    return '${row.read<int?>('revisions')}:${row.read<int>('pending')}'
        ':${row.read<int>('failed')}';
  }

  /// The revisions of [ids] whose data is stored for good: not a pin, and
  /// not an upload still pending or one that failed. Binds one variable per
  /// drive id.
  String _permanentRevisions(List<String> ids) => '''
        r.driveId IN (${List.filled(ids.length, '?').join(', ')})
        AND r.pinnedDataOwnerAddress IS NULL
        AND NOT EXISTS (
          SELECT 1 FROM network_transactions t
          WHERE t.id = r.dataTxId
            AND t.status IN ('${TransactionStatus.pending}',
                             '${TransactionStatus.failed}')
        )''';

  /// Which of [txIds] [driveIds] are made of, as sync recorded them: the
  /// metadata and data of every file revision, the metadata of every folder
  /// and drive revision, and the bundles any of them travelled in.
  ///
  /// What makes a wallet's transaction ArDrive storage, for the AR it paid
  /// directly - the same drives the permanence panel sizes, known the way
  /// sync knows them rather than guessed from an App-Name tag.
  ///
  /// Asked about the transactions in hand, never for the whole set: a drive
  /// of 100,000 files is made of 400,000 of them, which took a second and a
  /// half to read out natively and more on the web, where every row crosses
  /// to the page from the database worker. Asked in batches of
  /// [_txLookupBatch], to stay well inside SQLite's limit on variables.
  Future<Set<String>> arDriveTransactionsAmong(
    Iterable<String> driveIds,
    Iterable<String> txIds,
  ) async {
    final drives = driveIds.toList();
    final candidates = txIds.toSet().toList();

    if (drives.isEmpty || candidates.isEmpty) {
      return {};
    }

    final drivePlaceholders = List.filled(drives.length, '?').join(', ');
    final found = <String>{};

    for (var i = 0; i < candidates.length; i += _txLookupBatch) {
      final batch = candidates.sublist(
          i, math.min(i + _txLookupBatch, candidates.length));
      final txPlaceholders = List.filled(batch.length, '?').join(', ');
      // The transaction first: dataTxId has an index, and for the rest
      // SQLite checks each row against the batch in one pass.
      String among(String column, String table) => '''
        SELECT $column AS tx FROM $table
        WHERE $column IN ($txPlaceholders) AND driveId IN ($drivePlaceholders)''';

      final rows = await customSelect(
        [
          among('dataTxId', 'file_revisions'),
          among('metadataTxId', 'file_revisions'),
          among('bundledIn', 'file_revisions'),
          among('metadataTxId', 'folder_revisions'),
          among('metadataTxId', 'drive_revisions'),
          among('bundledIn', 'drive_revisions'),
        ].join('\nUNION '),
        variables: [
          for (var branch = 0; branch < 6; branch++) ...[
            for (final tx in batch) Variable.withString(tx),
            for (final drive in drives) Variable.withString(drive),
          ],
        ],
        readsFrom: {fileRevisions, folderRevisions, driveRevisions},
      ).get();

      found.addAll(rows.map((row) => row.read<String>('tx')));
    }

    return found;
  }

  static const _txLookupBatch = 300;

  /// Undoes names damaged by reading drive snapshots as Latin-1, in every
  /// table that keeps one: drives, folders and files, and their revisions.
  /// Returns how many it repaired.
  ///
  /// Snapshots were read a byte at a time until the fix beside this, so a
  /// drive synced from one stored every name with an em dash, an accent or
  /// any other character past ASCII in damaged form - "A â B" for "A — B".
  /// Changes only what [repairMisdecodedUtf8] recognises as that damage, so a
  /// name that was never damaged is left as it is; and the views watching
  /// these tables update as the names change.
  Future<int> repairMisdecodedNames() => transaction(() async {
        // Read everything first and write it in one batch: on the web every
        // statement is a round trip to the database worker
        // (docs/WEB_DATABASE.md), and this runs before a sync shows any
        // progress, so a drive of thousands of non-ASCII names must not cost
        // thousands of awaited updates. The views watching these tables hear
        // about it once per table rather than once per row.
        final repairs = <({TableInfo table, int rowId, String name})>[];

        for (final table in <TableInfo>[
          db.drives,
          db.driveRevisions,
          db.folderEntries,
          db.folderRevisions,
          db.fileEntries,
          db.fileRevisions,
        ]) {
          // Only names with something past printable ASCII can be damaged.
          final rows = await customSelect(
            'SELECT rowid AS r, name FROM ${table.actualTableName} '
            "WHERE name GLOB '*[^ -~]*'",
            readsFrom: {table},
          ).get();

          for (final row in rows) {
            final stored = row.read<String>('name');
            final fixed = repairMisdecodedUtf8(stored);

            if (fixed != stored) {
              repairs
                  .add((table: table, rowId: row.read<int>('r'), name: fixed));
            }
          }
        }

        if (repairs.isNotEmpty) {
          await batch((b) {
            for (final repair in repairs) {
              b.customStatement(
                'UPDATE ${repair.table.actualTableName} '
                'SET name = ? WHERE rowid = ?',
                [repair.name, repair.rowId],
                [TableUpdate.onTable(repair.table, kind: UpdateKind.update)],
              );
            }
          });
        }

        return repairs.length;
      });

  /// Whether any transaction is still waiting to be resolved as confirmed or
  /// failed.
  ///
  /// Asks only whether one exists - `LIMIT 1` against the status index - rather
  /// than reading every pending row the way [pendingTransactions] does. The
  /// caller only needs the yes/no, and a wallet mid-upload can have thousands.
  Future<bool> hasPendingTransactions() async {
    final query = selectOnly(networkTransactions)
      ..addColumns([networkTransactions.id])
      ..where(networkTransactions.status.equals(TransactionStatus.pending))
      ..limit(1);

    return (await query.get()).isNotEmpty;
  }
}

/// What the local database holds for one drive.
///
/// Deliberately not "what the drive contains": both numbers count synced rows,
/// so they are a description of this device, not of Arweave.
class DriveContentSummary extends Equatable {
  const DriveContentSummary({
    required this.fileCount,
    required this.totalSize,
  });

  static const empty = DriveContentSummary(fileCount: 0, totalSize: 0);

  /// File entries stored locally for this drive.
  ///
  /// Files only, and named for it. It was `itemCount`, described as "folders
  /// are not items here" - while the sync counts a folder as an item and says
  /// so on the same page, so a drive of three folders and two files read
  /// "Found 5 items", "5 items changed" and "2 items" at once. An item is
  /// whatever a sync writes, a file or a folder; this is not that number and
  /// no longer borrows its word.
  final int fileCount;

  /// The sum of those files' sizes, in bytes.
  final int totalSize;

  @override
  List<Object?> get props => [fileCount, totalSize];
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

/// Data stored permanently in one year: see [DriveDao.permanentDataByYear].
class PermanentData extends Equatable {
  const PermanentData({required this.bytes, required this.items});

  final int bytes;

  /// Pieces of data, each counted once however many files or versions
  /// point at it.
  final int items;

  @override
  List<Object> get props => [bytes, items];
}
