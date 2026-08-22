import 'dart:convert';

import 'package:ardrive/arns/utils/parse_assigned_names_from_string.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/file_entity.dart' show Thumbnail;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/services/license/license_service.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
// `isNull` / `isNotNull` are matchers here, not SQL expression builders.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

/// The acceptance test for the whole artifact: a drive published by one client
/// and opened by another has to *render*.
///
/// Every other test in this directory asks whether rows landed. This one asks
/// the only question that matters to a user, and it asks it the way the app
/// does — through `DriveDao.watchFolderContents`, which is what
/// `DriveDetailCubit` listens to, which is what paints the file list.
///
/// That query
/// (`filesInFolderWithLicenseAndRevisionTransactions`,
/// `lib/models/queries/drive_queries.drift`) **INNER JOINs**
/// `network_transactions` twice, through a correlated subselect that picks the
/// newest `file_revisions` row for each file and reads its `metadataTxId` and
/// `dataTxId`. A `file_entries` row with no revision behind it fails the ON
/// condition and is dropped from the result — silently, in every folder. So an
/// artifact carrying entries alone imports a drive that shows nothing, and
/// because the import advances the watermark past the range those revisions
/// live in, it does not heal either.
///
/// Hence: the payload carries revisions, and `network_transactions` is
/// regenerated from them on the way in.
void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';

  /// A file whose metadata was revised after it was created: the newest
  /// revision is the one the file list must resolve its transactions from.
  const revisedFileId = 'revised-file-id';
  const firstMetadataTxId = 'revised-file-metadata-tx-1';
  const firstDataTxId = 'revised-file-data-tx-1';
  const latestMetadataTxId = 'revised-file-metadata-tx-2';
  const latestDataTxId = 'revised-file-data-tx-2';

  /// A file the user attached a licence to. The licence join is a LEFT JOIN,
  /// so losing it hides nothing — it silently drops the licence instead.
  const licensedFileId = 'licensed-file-id';
  const licenseTxId = 'licensed-file-license-tx';

  final createdAt = DateTime(2024, 1, 1);
  final revisedAt = DateTime(2024, 3, 1);

  // ---------------------------------------------------------------------
  // Fixtures for the fidelity group, below.
  //
  // Every value here is deliberately *not* the column's default and not a
  // value any other row in this file uses. A `thumbnail` asserted equal to
  // null, or an `isHidden` asserted equal to `false`, would pass just as well
  // against an import that dropped the column on the floor.
  // ---------------------------------------------------------------------

  /// The file that carries one of everything.
  const decoratedFileId = 'decorated-file-id';
  const decoratedMetadataTxId = 'decorated-file-metadata-tx';
  const decoratedDataTxId = 'decorated-file-data-tx';
  const decoratedLicenseTxId = 'decorated-file-license-tx';
  const decoratedFallbackTxId = 'decorated-file-fallback-tx';
  const decoratedThumbSmallTxId = 'decorated-file-thumbnail-small-tx';
  const decoratedThumbLargeTxId = 'decorated-file-thumbnail-large-tx';

  /// Two variants, not one: a list that arrives with its order or its second
  /// element missing is a different bug from a list that does not arrive.
  const decoratedThumbnail = '{"variants":['
      '{"name":"small","txId":"$decoratedThumbSmallTxId",'
      '"size":8137,"width":128,"height":96},'
      '{"name":"large","txId":"$decoratedThumbLargeTxId",'
      '"size":31044,"width":512,"height":384}]}';

  /// Nested, and with a key order no re-serialiser would reproduce by luck.
  const decoratedCustomJson =
      '{"zeta":"last","camera":{"body":"Leica M6","lens":"35mm"},"iso":400}';
  const decoratedCustomTags = '[{"name":"Topic","value":"holiday"},'
      '{"name":"Topic","value":"1998"}]';

  /// The shape `DriveDao._encodeAssignedNames` writes and
  /// `parseAssignedNamesFromString` reads: an object, not a bare array.
  const decoratedAssignedNames =
      '{"assignedNames":["holiday-1998","holiday_1998_backup"]}';
  const decoratedNames = ['holiday-1998', 'holiday_1998_backup'];

  const decoratedPinnedOwner = 'pinned-data-owner-address-not-the-drive-owner';
  const decoratedOriginalOwner = 'original-owner-of-the-imported-file';
  const decoratedImportSource = 'the-manifest-tx-this-file-was-imported-from';
  const decoratedContentType = 'image/jpeg';
  const decoratedSize = 987654;

  /// Sub-second on purpose. Drift stores `DATETIME` as unix *seconds*, so the
  /// producer's own database truncates these before the export ever sees
  /// them — which is exactly why the assertions below compare the consumer
  /// against the producer's stored row rather than against these literals.
  final decoratedModifiedAt = DateTime(2024, 5, 17, 13, 45, 12, 345);
  final decoratedCreatedAt = DateTime(2024, 5, 17, 13, 46, 30, 678);
  final decoratedUpdatedAt = DateTime(2024, 6, 2, 9, 15, 44, 901);

  /// Hidden on both sides of the entity split, because the column is on both
  /// tables and the UI reads both.
  const hiddenFileId = 'hidden-file-id';
  const hiddenFolderId = 'hidden-folder-id';

  /// The null path: a file whose every optional column is unset. Exercised
  /// alongside the populated one so that "carries the value" and "carries the
  /// absence of the value" are two different assertions.
  const bareFileId = 'bare-file-id';

  /// Drives with shapes the seed above does not have.
  const foldersOnlyDriveId = 'folders-only-drive-id';
  const foldersOnlyRootId = 'folders-only-root-folder-id';
  const foldersOnlyChildId = 'folders-only-child-folder-id';
  const rootOnlyDriveId = 'root-only-drive-id';
  const rootOnlyRootId = 'root-only-root-folder-id';

  final codec = DriveStateEnvelopeCodec();
  final aesGcm = AesGcm.with256bits();

  late Wallet owner;
  late String ownerAddress;
  late SecretKey driveKey;

  /// The two chains, resolved rather than fabricated.
  late DriveStateProtection privateDrive;
  late DriveStateProtection publicDrive;

  late Database producerDb;
  late Database consumerDb;
  late DriveStateImporter importer;

  setUpAll(() async {
    // Producer and consumer are two databases on purpose: that is the whole
    // point of an artifact.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    owner = await Wallet.generate();
    ownerAddress = await owner.getAddress();
    driveKey = await aesGcm.newSecretKey();
    privateDrive = DriveStateProtection.forDrive(
      privacy: DrivePrivacyTag.private,
      driveKey: driveKey,
    ).protection!;
    publicDrive = DriveStateProtection.forDrive(
      privacy: DrivePrivacyTag.public,
      driveKey: null,
    ).protection!;
  });

  /// The producer's drive, seeded the way sync leaves one: entries, the
  /// revisions behind them, and a `network_transactions` row per transaction
  /// those revisions name.
  Future<void> seedProducer() async {
    await producerDb.batch((batch) {
      batch.insert(
        producerDb.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: ownerAddress,
          name: 'a published drive',
          privacy: DrivePrivacyTag.private,
          lastBlockHeight: const Value(900),
          lastUpdated: Value(revisedAt),
        ),
      );

      batch.insertAll(producerDb.folderEntries, [
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'a published drive',
          path: '',
          lastUpdated: Value(createdAt),
        ),
        FolderEntriesCompanion.insert(
          id: nestedFolderId,
          driveId: driveId,
          parentFolderId: const Value(rootFolderId),
          name: 'a nested folder',
          path: '',
          lastUpdated: Value(createdAt),
        ),
      ]);

      batch.insertAll(producerDb.folderRevisions, [
        FolderRevisionsCompanion.insert(
          folderId: rootFolderId,
          driveId: driveId,
          name: 'a published drive',
          metadataTxId: 'root-folder-metadata-tx',
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
        ),
        FolderRevisionsCompanion.insert(
          folderId: nestedFolderId,
          driveId: driveId,
          parentFolderId: const Value(rootFolderId),
          name: 'a nested folder',
          metadataTxId: 'nested-folder-metadata-tx',
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
        ),
      ]);

      batch.insert(
        producerDb.driveRevisions,
        DriveRevisionsCompanion.insert(
          driveId: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: ownerAddress,
          name: 'a published drive',
          privacy: DrivePrivacyTag.private,
          metadataTxId: 'drive-metadata-tx',
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
        ),
      );

      batch.insertAll(producerDb.fileEntries, [
        // The entry row always reflects the newest revision.
        FileEntriesCompanion.insert(
          id: revisedFileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'renamed.txt',
          dataTxId: latestDataTxId,
          size: 1024,
          path: '',
          dataContentType: const Value('text/plain'),
          lastModifiedDate: revisedAt,
          dateCreated: Value(createdAt),
          lastUpdated: Value(revisedAt),
        ),
        FileEntriesCompanion.insert(
          id: licensedFileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'licensed.png',
          dataTxId: 'licensed-file-data-tx',
          size: 2048,
          path: '',
          dataContentType: const Value('image/png'),
          licenseTxId: const Value(licenseTxId),
          lastModifiedDate: createdAt,
          dateCreated: Value(createdAt),
          lastUpdated: Value(createdAt),
        ),
      ]);

      batch.insertAll(producerDb.fileRevisions, [
        FileRevisionsCompanion.insert(
          fileId: revisedFileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'original.txt',
          size: 1024,
          lastModifiedDate: createdAt,
          metadataTxId: firstMetadataTxId,
          dataTxId: firstDataTxId,
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
          dataContentType: const Value('text/plain'),
        ),
        FileRevisionsCompanion.insert(
          fileId: revisedFileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'renamed.txt',
          size: 1024,
          lastModifiedDate: revisedAt,
          metadataTxId: latestMetadataTxId,
          dataTxId: latestDataTxId,
          action: RevisionAction.rename,
          dateCreated: Value(revisedAt),
          dataContentType: const Value('text/plain'),
        ),
        FileRevisionsCompanion.insert(
          fileId: licensedFileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'licensed.png',
          size: 2048,
          lastModifiedDate: createdAt,
          metadataTxId: 'licensed-file-metadata-tx',
          dataTxId: 'licensed-file-data-tx',
          licenseTxId: const Value(licenseTxId),
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
          dataContentType: const Value('image/png'),
        ),
      ]);

      batch.insert(
        producerDb.licenses,
        LicensesCompanion.insert(
          fileId: licensedFileId,
          driveId: driveId,
          dataTxId: 'licensed-file-data-tx',
          licenseTxType: LicenseTxType.assertion.name,
          licenseTxId: licenseTxId,
          licenseType: LicenseType.udl.name,
          dateCreated: Value(createdAt),
        ),
      );

      batch.insertAll(producerDb.networkTransactions, [
        for (final txId in [
          'drive-metadata-tx',
          'root-folder-metadata-tx',
          'nested-folder-metadata-tx',
          firstMetadataTxId,
          firstDataTxId,
          latestMetadataTxId,
          latestDataTxId,
          'licensed-file-metadata-tx',
          'licensed-file-data-tx',
          licenseTxId,
        ])
          NetworkTransactionsCompanion.insert(
            id: txId,
            status: const Value(TransactionStatus.confirmed),
            dateCreated: Value(createdAt),
          ),
      ]);
    });
  }

  /// The consumer, as a client that has attached the drive but not synced it:
  /// a drive row with its key material and nothing else.
  Future<void> attachDriveToConsumer({
    String id = driveId,
    String root = rootFolderId,
    String name = 'a published drive',
  }) =>
      consumerDb.into(consumerDb.drives).insert(
            DrivesCompanion.insert(
              id: id,
              rootFolderId: root,
              ownerAddress: ownerAddress,
              name: name,
              privacy: DrivePrivacyTag.private,
              encryptedKey: Value(Uint8List.fromList([1, 2, 3, 4])),
              keyEncryptionIv: Value(Uint8List.fromList([5, 6, 7])),
              driveKeyGenerated: const Value(true),
              lastBlockHeight: const Value(0),
              lastUpdated: Value(DateTime(2020)),
            ),
          );

  /// Export, seal, and hand back exactly what a consumer receives: the
  /// transaction body and the tags an indexer reported for it.
  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      publishArtifact({
    String drive = driveId,
    DriveStateProtection? protection,
  }) async {
    final export = await exportDriveState(producerDb.driveDao, drive);
    final payload = jsonEncode(export.toJson());

    final sealed = await codec.seal(
      plaintext: Uint8List.fromList(utf8.encode(payload)),
      protection: protection ?? privateDrive,
      wallet: owner,
    );
    expect(sealed.isSealed, isTrue, reason: sealed.toString());
    final envelope = sealed.envelope!;

    return (
      candidate: DriveStateArtifactCandidate(
        txId: 'artifact-tx-id',
        ownerAddress: ownerAddress,
        tags: {
          EntityTag.arFs: '0.15',
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: drive,
          EntityTag.driveStateId: 'drive-state-id',
          EntityTag.stateVersion: '1.0',
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '${export.coverage.blockStart}',
          EntityTag.blockEnd: '${export.coverage.blockEnd}',
          EntityTag.entityCount: '${export.entityCount}',
          // Written from what was actually sealed, so a public drive's
          // artifact carries neither tag - which is how a reader tells the
          // two chains apart.
          if (envelope.isEncrypted) EntityTag.cipher: Cipher.aes256,
          if (envelope.isEncrypted)
            EntityTag.cipherIv: envelope.cipherIvAsBase64!,
        },
        minedAtHeight: export.coverage.blockEnd,
      ),
      body: envelope.body,
    );
  }

  Future<DriveStateImportResult> publishAndImport({
    String drive = driveId,
    DriveStateProtection? protection,
  }) async {
    final artifact = await publishArtifact(
      drive: drive,
      protection: protection,
    );
    return importer.import(
      candidate: artifact.candidate,
      body: artifact.body,
      protection: protection ?? privateDrive,
      expectedOwnerAddress: ownerAddress,
    );
  }

  setUp(() async {
    producerDb = getTestDb();
    consumerDb = getTestDb();
    importer = DriveStateImporter(consumerDb.driveDao, codec: codec);

    await seedProducer();
    await attachDriveToConsumer();
  });

  tearDown(() async {
    await consumerDb.close();
    await producerDb.close();
  });

  /// The producer's own database is the control. If these assertions ever
  /// fail, the seed is wrong and nothing below means anything.
  test('the producer renders its own drive', () async {
    final contents = await producerDb.driveDao
        .watchFolderContents(driveId, folderId: rootFolderId)
        .first;

    expect(contents.files, hasLength(2));
    expect(contents.subfolders.map((f) => f.id), [nestedFolderId]);
  });

  group('a drive restored from an artifact', () {
    test('renders its files the way the file list asks for them', () async {
      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      final contents = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first;

      // The assertion this whole lane exists for. An import carrying entries
      // alone lands both `file_entries` rows and returns none of them here,
      // because the query's two INNER JOINs onto `network_transactions` have
      // no `file_revisions` row to reach them through.
      expect(
        contents.files.map((f) => f.id).toSet(),
        {revisedFileId, licensedFileId},
        reason: 'the file list must render every imported file',
      );
      expect(contents.subfolders.map((f) => f.id), [nestedFolderId]);
      expect(contents.folder.id, rootFolderId);
    });

    test('resolves each file to the transactions of its newest revision',
        () async {
      await publishAndImport();

      final contents = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first;
      final revised = contents.files.firstWhere((f) => f.id == revisedFileId);

      expect(revised.name, 'renamed.txt');
      expect(revised.metadataTx.id, latestMetadataTxId);
      expect(revised.dataTx.id, latestDataTxId);
      expect(revised.metadataTx.status, TransactionStatus.confirmed);
      expect(revised.dataTx.status, TransactionStatus.confirmed);
      expect(
        fileStatusFromTransactions(revised.metadataTx, revised.dataTx),
        TransactionStatus.confirmed,
        reason: 'a restored drive must not show every file as pending',
      );
    });

    test('keeps the licence the user attached to their own file', () async {
      await publishAndImport();

      final contents = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first;
      final licensed = contents.files.firstWhere((f) => f.id == licensedFileId);

      expect(licensed.license, isNot(null),
          reason: 'the licence join is a LEFT JOIN, so a missing licenses '
              'row hides nothing and drops the licence instead');
      expect(licensed.license!.licenseTxId, licenseTxId);
      expect(licensed.license!.licenseType, LicenseType.udl.name);
    });

    test('carries the whole version history, not just the newest revision',
        () async {
      await publishAndImport();

      final revisions = await consumerDb.driveDao
          .latestFileRevisionsByFileIdWithLicenseAndTransactions(
            driveId: driveId,
            fileId: revisedFileId,
          )
          .get();

      // The file details panel lists every revision. Publishing only the
      // newest would cost 5% fewer rows and lose the history outright.
      expect(revisions, hasLength(2));
      expect(
        revisions.map((r) => r.metadataTxId),
        [latestMetadataTxId, firstMetadataTxId],
      );
      expect(revisions.first.metadataTx.id, latestMetadataTxId);
      expect(revisions.first.dataTx.id, latestDataTxId);
    });

    test('restores the drive and folder revisions too', () async {
      await publishAndImport();

      final driveRevisions = await consumerDb.driveDao
          .latestDriveRevisionsByDriveIdWithTransactions(driveId: driveId)
          .get();
      final folderRevisions = await consumerDb.driveDao
          .latestFolderRevisionsByFolderIdWithTransactions(
            driveId: driveId,
            folderId: nestedFolderId,
          )
          .get();

      expect(driveRevisions, hasLength(1));
      expect(driveRevisions.single.metadataTx.id, 'drive-metadata-tx');
      expect(folderRevisions, hasLength(1));
      expect(folderRevisions.single.metadataTx.id, 'nested-folder-metadata-tx');
    });
  });

  /// The same acceptance question, for a public drive.
  ///
  /// A public drive's artifact is the private chain with the encryption step
  /// absent, and the point of this group is that *absent* is the only
  /// difference: the same rows, the same revisions, the same licence, the same
  /// values, rendered through the same query the file list uses.
  group('a public drive restored from an artifact', () {
    setUp(() async {
      // Public on both sides. The producer's row is what the payload's
      // `privacy` field is read from, and the consumer's is what the reader
      // cross-checks the artifact's cipher-presence against - so they have to
      // agree, and a real pair of clients holding the same drive always does.
      await producerDb.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
      ));
      await consumerDb.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
        encryptedKey: Value(null),
        keyEncryptionIv: Value(null),
        driveKeyGenerated: Value(false),
      ));
    });

    Future<DriveStateImportResult> publishAndImportPublicly() =>
        publishAndImport(protection: publicDrive);

    test('publishes a body with no cipher tags on it', () async {
      final artifact = await publishArtifact(protection: publicDrive);

      expect(artifact.candidate.cipher, isNull);
      expect(artifact.candidate.cipherIv, isNull);
      expect(
        artifact.candidate.tags.containsKey(EntityTag.cipher),
        isFalse,
      );
    });

    test('renders its files the way the file list asks for them', () async {
      final result = await publishAndImportPublicly();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      final contents = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first
          .timeout(const Duration(seconds: 10));

      expect(
        contents.files.map((f) => f.id).toSet(),
        {revisedFileId, licensedFileId},
      );
      expect(contents.subfolders.map((f) => f.id), [nestedFolderId]);
      expect(contents.folder.id, rootFolderId);
    });

    test('carries the same values a private drive would', () async {
      await publishAndImportPublicly();

      final contents = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first
          .timeout(const Duration(seconds: 10));

      final revised = contents.files.firstWhere((f) => f.id == revisedFileId);
      expect(revised.name, 'renamed.txt');
      expect(revised.metadataTx.id, latestMetadataTxId);
      expect(revised.dataTx.id, latestDataTxId);
      expect(
        fileStatusFromTransactions(revised.metadataTx, revised.dataTx),
        TransactionStatus.confirmed,
      );

      final licensed = contents.files.firstWhere((f) => f.id == licensedFileId);
      expect(licensed.license, isNotNull);
      expect(licensed.license!.licenseTxId, licenseTxId);
      expect(licensed.license!.licenseType, LicenseType.udl.name);
    });

    test('carries the whole version history', () async {
      await publishAndImportPublicly();

      final revisions = await consumerDb.driveDao
          .latestFileRevisionsByFileIdWithLicenseAndTransactions(
            driveId: driveId,
            fileId: revisedFileId,
          )
          .get();

      expect(revisions, hasLength(2));
      expect(
        revisions.map((r) => r.metadataTxId),
        [latestMetadataTxId, firstMetadataTxId],
      );
    });

    test('leaves the drive public and on the artifact\'s watermark', () async {
      final result = await publishAndImportPublicly();

      final drive = await (consumerDb.select(consumerDb.drives)
            ..where((d) => d.id.equals(driveId)))
          .getSingle();

      expect(drive.privacy, DrivePrivacyTag.public);
      expect(drive.lastBlockHeight, 900);
      expect(result.stats!.watermark, 900);
      // Never conjured: an import that gave a public drive key material would
      // be inventing something the payload cannot carry.
      expect(drive.encryptedKey, isNull);
      expect(drive.keyEncryptionIv, isNull);
    });
  });

  /// The cipher/privacy cross-check, end to end: a genuine artifact, correctly
  /// signed by the drive's real owner, offered to a drive of the other
  /// privacy.
  ///
  /// These are not malformed artifacts. Each one opens perfectly for the drive
  /// it was made for; what is wrong is only which drive it is being read into.
  group('an artifact whose cipher contradicts the drive', () {
    test('a plaintext artifact is refused for a private drive', () async {
      // The producer's drive is still private here, so the payload says
      // `private` and only the *sealing* is wrong - which is precisely the
      // shape a buggy producer would publish, and the one that must never be
      // accepted.
      final artifact = await publishArtifact(protection: publicDrive);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      expect(result.detail, contains('never published in the clear'));

      // And nothing landed.
      final files = await (consumerDb.select(consumerDb.fileEntries)
            ..where((f) => f.driveId.equals(driveId)))
          .get();
      expect(files, isEmpty);
    });

    test('an encrypted artifact is refused for a public drive', () async {
      await consumerDb.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
      ));

      final artifact = await publishArtifact(protection: privateDrive);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: publicDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      // Not `decryptFailed`, which would blame a key this reader never had.
      expect(result.outcome, isNot(DriveStateOutcome.decryptFailed));

      final files = await (consumerDb.select(consumerDb.fileEntries)
            ..where((f) => f.driveId.equals(driveId)))
          .get();
      expect(files, isEmpty);
    });
  });

  // =====================================================================
  // Fidelity: not "did rows land", but "did the values inside them".
  //
  // The columns below are all classified, all named in the export's
  // projection and all named in the import's companions — and until this
  // group existed, nothing asserted that any of them arrived. A structural
  // guarantee is not a behavioural one: a column can be selected and then
  // dropped by a `_fromRow` that never reads it, or read and then dropped by
  // a `toJson` that never writes it, and every structural test in this
  // directory still passes.
  // =====================================================================
  group('the values a file carries', () {
    /// A folder that must open within a few seconds or has not opened at all.
    ///
    /// `watchFolderContents` combines three streams and emits only when all
    /// three have; if the folder row is missing, the combined stream never
    /// emits and `.first` waits for ever. Bounding it turns "the drive does
    /// not open" from a suite that hangs into an assertion that fails.
    Future<FolderWithContents> openFolder(String folderId) =>
        consumerDb.driveDao
            .watchFolderContents(driveId, folderId: folderId)
            .first
            .timeout(const Duration(seconds: 10));

    Future<FileWithLicenseAndLatestRevisionTransactions> renderedFile(
      String fileId, {
      String folderId = rootFolderId,
    }) async {
      final contents = await openFolder(folderId);
      return contents.files.firstWhere(
        (f) => f.id == fileId,
        orElse: () => throw StateError(
          '$fileId is not in $folderId: ${contents.files.map((f) => f.id)}',
        ),
      );
    }

    Future<FileEntry> fileRow(Database db, String fileId) =>
        (db.select(db.fileEntries)
              ..where((f) => f.driveId.equals(driveId) & f.id.equals(fileId)))
            .getSingle();

    Future<FolderEntry> folderRow(Database db, String folderId) =>
        (db.select(db.folderEntries)
              ..where((f) => f.driveId.equals(driveId) & f.id.equals(folderId)))
            .getSingle();

    Future<List<FileRevision>> fileRevisionRows(
      Database db,
      String fileId,
    ) =>
        (db.select(db.fileRevisions)
              ..where(
                  (r) => r.driveId.equals(driveId) & r.fileId.equals(fileId))
              ..orderBy([(r) => OrderingTerm.asc(r.dateCreated)]))
            .get();

    /// One file carrying a non-default value in every optional column, one
    /// hidden file, one hidden folder, and one file carrying nothing at all.
    setUp(() async {
      await producerDb.batch((batch) {
        batch.insert(
          producerDb.folderEntries,
          FolderEntriesCompanion.insert(
            id: hiddenFolderId,
            driveId: driveId,
            parentFolderId: const Value(rootFolderId),
            name: 'a hidden folder',
            path: '',
            isHidden: const Value(true),
            lastUpdated: Value(createdAt),
          ),
        );

        batch.insert(
          producerDb.folderRevisions,
          FolderRevisionsCompanion.insert(
            folderId: hiddenFolderId,
            driveId: driveId,
            parentFolderId: const Value(rootFolderId),
            name: 'a hidden folder',
            metadataTxId: 'hidden-folder-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
            isHidden: const Value(true),
          ),
        );

        batch.insertAll(producerDb.fileEntries, [
          FileEntriesCompanion.insert(
            id: decoratedFileId,
            driveId: driveId,
            // At the root, not in a subfolder: the seed above nests
            // everything, and a root-level file is the commonest shape there
            // is.
            parentFolderId: rootFolderId,
            name: 'holiday.jpg',
            dataTxId: decoratedDataTxId,
            size: decoratedSize,
            path: '',
            dataContentType: const Value(decoratedContentType),
            licenseTxId: const Value(decoratedLicenseTxId),
            bundledIn: const Value('decorated-file-bundle-tx'),
            thumbnail: const Value(decoratedThumbnail),
            pinnedDataOwnerAddress: const Value(decoratedPinnedOwner),
            customJsonMetadata: const Value(decoratedCustomJson),
            customGQLTags: const Value(decoratedCustomTags),
            isHidden: const Value(false),
            assignedNames: const Value(decoratedAssignedNames),
            fallbackTxId: const Value(decoratedFallbackTxId),
            originalOwner: const Value(decoratedOriginalOwner),
            importSource: const Value(decoratedImportSource),
            lastModifiedDate: decoratedModifiedAt,
            dateCreated: Value(decoratedCreatedAt),
            lastUpdated: Value(decoratedUpdatedAt),
          ),
          FileEntriesCompanion.insert(
            id: hiddenFileId,
            driveId: driveId,
            parentFolderId: rootFolderId,
            name: 'hidden.txt',
            dataTxId: 'hidden-file-data-tx',
            size: 11,
            path: '',
            isHidden: const Value(true),
            lastModifiedDate: createdAt,
            dateCreated: Value(createdAt),
            lastUpdated: Value(createdAt),
          ),
          // Every optional column left unset, in a subfolder, so the null
          // path and the nested path are both exercised.
          FileEntriesCompanion.insert(
            id: bareFileId,
            driveId: driveId,
            parentFolderId: nestedFolderId,
            name: 'bare.bin',
            dataTxId: 'bare-file-data-tx',
            size: 7,
            path: '',
            lastModifiedDate: createdAt,
            dateCreated: Value(createdAt),
            lastUpdated: Value(createdAt),
          ),
        ]);

        batch.insertAll(producerDb.fileRevisions, [
          FileRevisionsCompanion.insert(
            fileId: decoratedFileId,
            driveId: driveId,
            parentFolderId: rootFolderId,
            name: 'holiday.jpg',
            size: decoratedSize,
            lastModifiedDate: decoratedModifiedAt,
            dataContentType: const Value(decoratedContentType),
            metadataTxId: decoratedMetadataTxId,
            dataTxId: decoratedDataTxId,
            licenseTxId: const Value(decoratedLicenseTxId),
            thumbnail: const Value(decoratedThumbnail),
            bundledIn: const Value('decorated-file-bundle-tx'),
            dateCreated: Value(decoratedCreatedAt),
            customJsonMetadata: const Value(decoratedCustomJson),
            customGQLTags: const Value(decoratedCustomTags),
            action: RevisionAction.create,
            pinnedDataOwnerAddress: const Value(decoratedPinnedOwner),
            isHidden: const Value(false),
            assignedNames: const Value(decoratedAssignedNames),
            fallbackTxId: const Value(decoratedFallbackTxId),
            originalOwner: const Value(decoratedOriginalOwner),
            importSource: const Value(decoratedImportSource),
          ),
          FileRevisionsCompanion.insert(
            fileId: hiddenFileId,
            driveId: driveId,
            parentFolderId: rootFolderId,
            name: 'hidden.txt',
            size: 11,
            lastModifiedDate: createdAt,
            metadataTxId: 'hidden-file-metadata-tx',
            dataTxId: 'hidden-file-data-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
            isHidden: const Value(true),
          ),
          FileRevisionsCompanion.insert(
            fileId: bareFileId,
            driveId: driveId,
            parentFolderId: nestedFolderId,
            name: 'bare.bin',
            size: 7,
            lastModifiedDate: createdAt,
            metadataTxId: 'bare-file-metadata-tx',
            dataTxId: 'bare-file-data-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
        ]);

        batch.insert(
          producerDb.licenses,
          LicensesCompanion.insert(
            fileId: decoratedFileId,
            driveId: driveId,
            dataTxId: decoratedDataTxId,
            // Deliberately the other enum value from the seed's licence, so
            // an import that crossed the two rows would be visible.
            licenseTxType: LicenseTxType.composed.name,
            licenseTxId: decoratedLicenseTxId,
            licenseType: LicenseType.ccByNCND.name,
            bundledIn: const Value('decorated-licence-bundle-tx'),
            customGQLTags: const Value('[{"name":"License-Fee","value":"0"}]'),
            dateCreated: Value(decoratedCreatedAt),
          ),
        );

        batch.insertAll(producerDb.networkTransactions, [
          for (final txId in [
            'hidden-folder-metadata-tx',
            'hidden-file-metadata-tx',
            'hidden-file-data-tx',
            'bare-file-metadata-tx',
            'bare-file-data-tx',
            decoratedMetadataTxId,
            decoratedDataTxId,
            decoratedLicenseTxId,
          ])
            NetworkTransactionsCompanion.insert(
              id: txId,
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(createdAt),
            ),
        ]);
      });
    });

    test('carries a thumbnail the far side can still parse', () async {
      await publishAndImport();

      final rendered = await renderedFile(decoratedFileId);
      expect(rendered.thumbnail, decoratedThumbnail);

      // Not a string comparison: `data_table_item.dart` decodes this blob and
      // hands it to `Thumbnail.fromJson`, and a value that survives as a
      // string but no longer parses is a file whose preview is gone.
      final item = DriveDataTableItemMapper.toFileDataTableItem(
        rendered,
        0,
        true,
      );
      final Thumbnail? thumbnail = item.thumbnail;

      expect(thumbnail, isNotNull,
          reason: 'the file list builds its preview from this');
      expect(thumbnail!.variants.map((v) => v.name), ['small', 'large']);
      expect(thumbnail.variants.first.txId, decoratedThumbSmallTxId);
      expect(thumbnail.variants.first.size, 8137);
      expect(thumbnail.variants.first.width, 128);
      expect(thumbnail.variants.first.height, 96);
      expect(thumbnail.variants.last.txId, decoratedThumbLargeTxId);
      expect(thumbnail.variants.last.size, 31044);
      expect(thumbnail.variants.last.width, 512);
      expect(thumbnail.variants.last.height, 384);

      // The details panel reads the revision, not the entry.
      final revisions = await fileRevisionRows(consumerDb, decoratedFileId);
      expect(revisions.single.thumbnail, decoratedThumbnail);
    });

    test('carries the addresses and transaction ids that are not its own',
        () async {
      await publishAndImport();

      final entry = await fileRow(consumerDb, decoratedFileId);
      expect(entry.pinnedDataOwnerAddress, decoratedPinnedOwner);
      expect(entry.originalOwner, decoratedOriginalOwner);
      expect(entry.importSource, decoratedImportSource);
      expect(entry.fallbackTxId, decoratedFallbackTxId);
      expect(entry.bundledIn, 'decorated-file-bundle-tx');

      // `pinnedDataOwnerAddress` in particular: the confirmation query scopes
      // itself by exactly this address, so a pin that lost it is a file whose
      // data can never be confirmed again.
      final revision =
          (await fileRevisionRows(consumerDb, decoratedFileId)).single;
      expect(revision.pinnedDataOwnerAddress, decoratedPinnedOwner);
      expect(revision.originalOwner, decoratedOriginalOwner);
      expect(revision.importSource, decoratedImportSource);
      expect(revision.fallbackTxId, decoratedFallbackTxId);
      expect(revision.bundledIn, 'decorated-file-bundle-tx');

      // And through the query the file list runs, which is where the details
      // panel's "imported from" link comes from.
      final rendered = await renderedFile(decoratedFileId);
      expect(rendered.pinnedDataOwnerAddress, decoratedPinnedOwner);
      expect(rendered.originalOwner, decoratedOriginalOwner);
      expect(rendered.importSource, decoratedImportSource);
      expect(rendered.fallbackTxId, decoratedFallbackTxId);
    });

    test('carries the custom metadata blobs unaltered', () async {
      await publishAndImport();

      final entry = await fileRow(consumerDb, decoratedFileId);
      final revision =
          (await fileRevisionRows(consumerDb, decoratedFileId)).single;

      // Byte for byte, not merely equivalent. These blobs are re-emitted as
      // ArFS metadata on the next revision of the file, so a re-serialisation
      // that reordered keys would change what this client publishes about a
      // file it never edited.
      expect(entry.customJsonMetadata, decoratedCustomJson);
      expect(entry.customGQLTags, decoratedCustomTags);
      expect(revision.customJsonMetadata, decoratedCustomJson);
      expect(revision.customGQLTags, decoratedCustomTags);

      // And still valid JSON with the values intact, so that a change which
      // preserved the bytes but broke the encoding could not pass either.
      expect(
        jsonDecode(entry.customJsonMetadata!),
        {
          'zeta': 'last',
          'camera': {'body': 'Leica M6', 'lens': '35mm'},
          'iso': 400,
        },
      );
      expect((jsonDecode(entry.customGQLTags!) as List), hasLength(2));
    });

    test('carries assignedNames in the shape the file list parses', () async {
      await publishAndImport();

      final rendered = await renderedFile(decoratedFileId);
      expect(rendered.assignedNames, decoratedAssignedNames);

      // `data_table_item.dart` renders the ArNS names through this function,
      // which returns null for anything it cannot read — so a blob that
      // survived in a shape this cannot parse looks exactly like a file with
      // no names at all.
      expect(
        parseAssignedNamesFromString(rendered.assignedNames),
        decoratedNames,
      );
      expect(
        DriveDataTableItemMapper.toFileDataTableItem(rendered, 0, true)
            .assignedNames,
        decoratedNames,
      );

      final revision =
          (await fileRevisionRows(consumerDb, decoratedFileId)).single;
      expect(revision.assignedNames, decoratedAssignedNames);
      expect(
          parseAssignedNamesFromString(revision.assignedNames), decoratedNames);
    });

    test('carries the licence pointer and the licence row together', () async {
      await publishAndImport();

      final entry = await fileRow(consumerDb, decoratedFileId);
      expect(entry.licenseTxId, decoratedLicenseTxId);

      // The pointer alone is worthless. `licenses` is a separate section of
      // the payload and a separate statement on the way in, so the two can
      // part company without any single-table assertion noticing.
      final licences = await (consumerDb.select(consumerDb.licenses)
            ..where((l) =>
                l.driveId.equals(driveId) & l.fileId.equals(decoratedFileId)))
          .get();

      expect(licences, hasLength(1),
          reason: 'the file points at a licence row that has to exist');
      final licence = licences.single;
      expect(licence.licenseTxId, decoratedLicenseTxId);
      expect(licence.licenseType, LicenseType.ccByNCND.name);
      expect(licence.licenseTxType, LicenseTxType.composed.name);
      expect(licence.dataTxId, decoratedDataTxId);
      expect(licence.bundledIn, 'decorated-licence-bundle-tx');
      expect(licence.customGQLTags, '[{"name":"License-Fee","value":"0"}]');

      // And the join the file list runs resolves the same row, through the
      // newest revision's `licenseTxId` rather than the entry's.
      final rendered = await renderedFile(decoratedFileId);
      expect(rendered.license, isNotNull);
      expect(rendered.license!.licenseTxId, decoratedLicenseTxId);
      expect(rendered.license!.licenseType, LicenseType.ccByNCND.name);

      // Two licensed files in the drive, two distinct licences: an import
      // that carried one row for both would still satisfy everything above
      // if it happened to carry this one.
      final all = await (consumerDb.select(consumerDb.licenses)
            ..where((l) => l.driveId.equals(driveId)))
          .get();
      expect(
        all.map((l) => l.licenseTxId).toSet(),
        {decoratedLicenseTxId, licenseTxId},
      );
    });

    test('carries size, content type and the dates the row is keyed by',
        () async {
      await publishAndImport();

      final producerEntry = await fileRow(producerDb, decoratedFileId);
      final consumerEntry = await fileRow(consumerDb, decoratedFileId);

      expect(consumerEntry.size, decoratedSize);
      expect(consumerEntry.dataContentType, decoratedContentType);

      // Compared against the producer's *stored* row, not against the literal
      // the seed used: drift stores DATETIME as unix seconds, so the
      // sub-second component of the fixture is gone before the export runs.
      // What the artifact must not do is lose anything the database kept.
      expect(consumerEntry.lastModifiedDate, producerEntry.lastModifiedDate);
      expect(consumerEntry.dateCreated, producerEntry.dateCreated);
      expect(consumerEntry.lastUpdated, producerEntry.lastUpdated);

      expect(
        consumerEntry.lastModifiedDate.millisecondsSinceEpoch,
        producerEntry.lastModifiedDate.millisecondsSinceEpoch,
      );

      // A tripwire, not an assertion about the artifact. `_dateToJson` emits
      // epoch *milliseconds* while drift stores unix *seconds*, so today the
      // format is strictly wider than the storage and sub-second drift is
      // absorbed on both sides — which is why the fixture's `.345` is gone
      // here. If drift is ever configured to keep sub-second precision, that
      // slack disappears, `_dateToJson`'s resolution becomes load-bearing for
      // revision keys, and this is the line that says so first.
      expect(producerEntry.lastModifiedDate.millisecond, 0,
          reason: 'drift stores DATETIME as unix seconds');

      final producerRevision =
          (await fileRevisionRows(producerDb, decoratedFileId)).single;
      final consumerRevision =
          (await fileRevisionRows(consumerDb, decoratedFileId)).single;
      expect(consumerRevision.size, decoratedSize);
      expect(consumerRevision.dataContentType, decoratedContentType);
      expect(
        consumerRevision.lastModifiedDate,
        producerRevision.lastModifiedDate,
      );
      expect(consumerRevision.dateCreated, producerRevision.dateCreated);
    });

    test('a revision the consumer already synced is not duplicated', () async {
      // This is the assertion the date columns exist for.
      //
      // `file_revisions` is keyed by `(fileId, driveId, dateCreated)` and
      // lands with `insertOrIgnore`, so the artifact's copy of a revision is
      // the *same row* as the one this client already wrote during an
      // ordinary sync only if the date survived the trip exactly. A shift of
      // one second turns one revision into two, permanently, and the details
      // panel lists the file's history twice.
      //
      // Note what this catches that re-importing does not: two imports of one
      // payload shift alike and would still collide with each other. Only a
      // row that never went through the export can tell.
      final alreadySynced =
          (await fileRevisionRows(producerDb, decoratedFileId)).single;

      await consumerDb.batch((batch) {
        batch.insertAll(consumerDb.networkTransactions, [
          for (final txId in [
            decoratedMetadataTxId,
            decoratedDataTxId,
            decoratedLicenseTxId,
          ])
            NetworkTransactionsCompanion.insert(
              id: txId,
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(createdAt),
            ),
        ]);
        batch.insert(consumerDb.fileRevisions, alreadySynced);
      });

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      final revisions = await fileRevisionRows(consumerDb, decoratedFileId);
      expect(revisions, hasLength(1),
          reason: "the artifact's copy of this revision must be the row the "
              'consumer already held, not a second one beside it');
      expect(revisions.single.dateCreated, alreadySynced.dateCreated);
    });

    test('re-importing the same artifact does not fork a revision', () async {
      // The weaker half of the check above, kept because it is the case a
      // background sync actually produces: the same artifact is rediscovered
      // and re-imported on every pass once `blockEnd == localWatermark`.
      await publishAndImport();
      final afterFirst = await fileRevisionRows(consumerDb, decoratedFileId);

      final second = await publishAndImport();
      expect(second.outcome, DriveStateOutcome.used, reason: second.detail);

      final afterSecond = await fileRevisionRows(consumerDb, decoratedFileId);
      expect(afterSecond, hasLength(afterFirst.length));
      expect(afterSecond.single.dateCreated, afterFirst.single.dateCreated);

      final allRevisions = await (consumerDb.select(consumerDb.fileRevisions)
            ..where((r) => r.driveId.equals(driveId)))
          .get();
      expect(allRevisions, hasLength(6),
          reason: 'two for the revised file and one each for the licensed, '
              'decorated, hidden and bare ones — every file still holding '
              'exactly the revisions it had');
    });

    test('carries isHidden on files and on folders, both ways', () async {
      await publishAndImport();

      expect((await fileRow(consumerDb, hiddenFileId)).isHidden, isTrue);
      expect((await fileRow(consumerDb, decoratedFileId)).isHidden, isFalse);
      expect((await folderRow(consumerDb, hiddenFolderId)).isHidden, isTrue);
      expect((await folderRow(consumerDb, nestedFolderId)).isHidden, isFalse);

      final revisions = await (consumerDb.select(consumerDb.fileRevisions)
            ..where((r) =>
                r.driveId.equals(driveId) & r.fileId.equals(hiddenFileId)))
          .get();
      expect(revisions.single.isHidden, isTrue);

      final folderRevisions = await (consumerDb
              .select(consumerDb.folderRevisions)
            ..where((r) =>
                r.driveId.equals(driveId) & r.folderId.equals(hiddenFolderId)))
          .get();
      expect(folderRevisions.single.isHidden, isTrue);

      // The toggle that offers to show hidden items is driven by this query.
      // An import that dropped every flag would leave the user with hidden
      // files they can neither see nor be told about.
      expect(await consumerDb.driveDao.hasHiddenItems().getSingle(), isTrue);
    });

    test('a hidden file is left out where the explorer hides it', () async {
      await publishAndImport();

      final contents = await openFolder(rootFolderId);
      final items = [
        for (final (index, file) in contents.files.indexed)
          DriveDataTableItemMapper.toFileDataTableItem(file, index, true),
      ];

      // The predicate `DriveDetailDataList` applies when "show hidden" is
      // off (`drive_detail_data_list.dart`). Reproduced rather than mounted,
      // because the value under test is the flag on the row, and the widget
      // adds nothing but this line.
      final visible = items.where((item) => !item.isHidden).toList();

      expect(items.map((i) => i.id), contains(hiddenFileId),
          reason: 'the row itself must still arrive — hidden is not absent');
      expect(visible.map((i) => i.id), isNot(contains(hiddenFileId)));
      expect(visible.map((i) => i.id), contains(decoratedFileId));

      // Folders take the same path in the same list.
      final folders = [
        for (final (index, folder) in contents.subfolders.indexed)
          DriveDataTableItemMapper.fromFolderEntry(folder, index, true),
      ];
      expect(
        folders.where((f) => !f.isHidden).map((f) => f.id),
        isNot(contains(hiddenFolderId)),
      );
      expect(folders.map((f) => f.id), contains(hiddenFolderId));
    });

    test('carries a file whose optional columns are all null', () async {
      await publishAndImport();

      // The null path, alongside the populated one: an import that wrote a
      // default in place of a missing value — an empty string for a null
      // `dataContentType`, say — would be invisible to every assertion above.
      final bare = await fileRow(consumerDb, bareFileId);
      expect(bare.dataContentType, isNull);
      expect(bare.licenseTxId, isNull);
      expect(bare.bundledIn, isNull);
      expect(bare.thumbnail, isNull);
      expect(bare.pinnedDataOwnerAddress, isNull);
      expect(bare.customJsonMetadata, isNull);
      expect(bare.customGQLTags, isNull);
      expect(bare.assignedNames, isNull);
      expect(bare.fallbackTxId, isNull);
      expect(bare.originalOwner, isNull);
      expect(bare.importSource, isNull);
      expect(bare.isHidden, isFalse);
      expect(bare.size, 7);

      final revision = (await fileRevisionRows(consumerDb, bareFileId)).single;
      expect(revision.dataContentType, isNull);
      expect(revision.thumbnail, isNull);
      expect(revision.assignedNames, isNull);
      expect(revision.pinnedDataOwnerAddress, isNull);
      expect(revision.originalOwner, isNull);
      expect(revision.importSource, isNull);
      expect(revision.fallbackTxId, isNull);

      // And it renders, in the subfolder it lives in.
      final nested = await openFolder(nestedFolderId);
      expect(nested.files.map((f) => f.id), [bareFileId]);

      final item = DriveDataTableItemMapper.toFileDataTableItem(
        nested.files.single,
        0,
        true,
      );
      expect(item.thumbnail, isNull);
      expect(item.assignedNames, isNull);
    });
  });

  // =====================================================================
  // Shapes the seed above does not have. Each is a drive of its own in the
  // same producer database, which also demonstrates that the export is
  // scoped to the drive it was asked for.
  // =====================================================================
  group('drive shapes', () {
    Future<FolderWithContents> openDrive(String drive, String folder) =>
        consumerDb.driveDao
            .watchFolderContents(drive, folderId: folder)
            .first
            .timeout(const Duration(seconds: 10));

    test('a drive with folders and no files at all imports and opens',
        () async {
      await producerDb.batch((batch) {
        batch.insert(
          producerDb.drives,
          DrivesCompanion.insert(
            id: foldersOnlyDriveId,
            rootFolderId: foldersOnlyRootId,
            ownerAddress: ownerAddress,
            name: 'a drive of empty folders',
            privacy: DrivePrivacyTag.private,
            lastBlockHeight: const Value(700),
            lastUpdated: Value(createdAt),
          ),
        );
        batch.insert(
          producerDb.driveRevisions,
          DriveRevisionsCompanion.insert(
            driveId: foldersOnlyDriveId,
            rootFolderId: foldersOnlyRootId,
            ownerAddress: ownerAddress,
            name: 'a drive of empty folders',
            privacy: DrivePrivacyTag.private,
            metadataTxId: 'folders-only-drive-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
        );
        batch.insertAll(producerDb.folderEntries, [
          FolderEntriesCompanion.insert(
            id: foldersOnlyRootId,
            driveId: foldersOnlyDriveId,
            name: 'a drive of empty folders',
            path: '',
            lastUpdated: Value(createdAt),
          ),
          FolderEntriesCompanion.insert(
            id: foldersOnlyChildId,
            driveId: foldersOnlyDriveId,
            parentFolderId: const Value(foldersOnlyRootId),
            name: 'still empty',
            path: '',
            lastUpdated: Value(createdAt),
          ),
        ]);
        batch.insertAll(producerDb.folderRevisions, [
          FolderRevisionsCompanion.insert(
            folderId: foldersOnlyRootId,
            driveId: foldersOnlyDriveId,
            name: 'a drive of empty folders',
            metadataTxId: 'folders-only-root-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
          FolderRevisionsCompanion.insert(
            folderId: foldersOnlyChildId,
            driveId: foldersOnlyDriveId,
            parentFolderId: const Value(foldersOnlyRootId),
            name: 'still empty',
            metadataTxId: 'folders-only-child-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
        ]);
        batch.insertAll(producerDb.networkTransactions, [
          for (final txId in [
            'folders-only-drive-metadata-tx',
            'folders-only-root-metadata-tx',
            'folders-only-child-metadata-tx',
          ])
            NetworkTransactionsCompanion.insert(
              id: txId,
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(createdAt),
            ),
        ]);
      });

      await attachDriveToConsumer(
        id: foldersOnlyDriveId,
        root: foldersOnlyRootId,
        name: 'a drive of empty folders',
      );

      final result = await publishAndImport(drive: foldersOnlyDriveId);
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      final contents = await openDrive(foldersOnlyDriveId, foldersOnlyRootId);
      expect(contents.folder.id, foldersOnlyRootId);
      expect(contents.subfolders.map((f) => f.id), [foldersOnlyChildId]);
      expect(contents.files, isEmpty);

      // And nothing from the other drive leaked into it.
      final files = await (consumerDb.select(consumerDb.fileEntries)
            ..where((f) => f.driveId.equals(foldersOnlyDriveId)))
          .get();
      expect(files, isEmpty);
    });

    test('a drive with nothing but its root folder imports and opens',
        () async {
      await producerDb.batch((batch) {
        batch.insert(
          producerDb.drives,
          DrivesCompanion.insert(
            id: rootOnlyDriveId,
            rootFolderId: rootOnlyRootId,
            ownerAddress: ownerAddress,
            name: 'a brand new drive',
            privacy: DrivePrivacyTag.private,
            lastBlockHeight: const Value(500),
            lastUpdated: Value(createdAt),
          ),
        );
        batch.insert(
          producerDb.driveRevisions,
          DriveRevisionsCompanion.insert(
            driveId: rootOnlyDriveId,
            rootFolderId: rootOnlyRootId,
            ownerAddress: ownerAddress,
            name: 'a brand new drive',
            privacy: DrivePrivacyTag.private,
            metadataTxId: 'root-only-drive-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
        );
        batch.insert(
          producerDb.folderEntries,
          FolderEntriesCompanion.insert(
            id: rootOnlyRootId,
            driveId: rootOnlyDriveId,
            name: 'a brand new drive',
            path: '',
            lastUpdated: Value(createdAt),
          ),
        );
        batch.insert(
          producerDb.folderRevisions,
          FolderRevisionsCompanion.insert(
            folderId: rootOnlyRootId,
            driveId: rootOnlyDriveId,
            name: 'a brand new drive',
            metadataTxId: 'root-only-root-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
        );
        batch.insertAll(producerDb.networkTransactions, [
          for (final txId in [
            'root-only-drive-metadata-tx',
            'root-only-root-metadata-tx',
          ])
            NetworkTransactionsCompanion.insert(
              id: txId,
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(createdAt),
            ),
        ]);
      });

      await attachDriveToConsumer(
        id: rootOnlyDriveId,
        root: rootOnlyRootId,
        name: 'a brand new drive',
      );

      final result = await publishAndImport(drive: rootOnlyDriveId);
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      // The narrowest artifact there is. It still has to leave a drive that
      // opens: an empty root folder is a drive the user can upload into, a
      // root folder that resolves nowhere is a spinner.
      final contents = await openDrive(rootOnlyDriveId, rootOnlyRootId);
      expect(contents.folder.id, rootOnlyRootId);
      expect(contents.folder.name, 'a brand new drive');
      expect(contents.subfolders, isEmpty);
      expect(contents.files, isEmpty);

      // Opened by root id rather than by folder id, which is the path the
      // explorer takes when it has no folder selected.
      final byDrive = await consumerDb.driveDao
          .watchFolderContents(rootOnlyDriveId)
          .first
          .timeout(const Duration(seconds: 10));
      expect(byDrive.folder.id, rootOnlyRootId);
    });
  });
}
