import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart'
    as sqlite;
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';
import '../artifact_sql.dart';

/// The one version this build writes and reads. Fixtures follow the constant
/// rather than restating it — restating it is how a fixture ends up asserting
/// a version the code no longer speaks.
String get currentVersionString => DriveStateFormatVersion.current.toString();

/// The import is exercised end to end, through a real seal and a real
/// in-memory database, because every one of its rules is about the seam
/// between the two: what the tags promised, what the payload held, and what
/// the database already knew.
///
/// There is no fixture key material and no fixture wallet. Everything is
/// generated here.
void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';
  const otherDriveId = 'other-drive-id';

  final codec = DriveStateEnvelopeCodec();
  final aesGcm = AesGcm.with256bits();

  late Wallet owner;
  late String ownerAddress;
  late SecretKey driveKey;

  /// The two protections, resolved the only way they can be: from a drive's
  /// `privacy` column and the key that came with it.
  late DriveStateProtection privateDrive;

  /// The public drive's protection. Every test that reads one is about the
  /// cross-check, or about a public drive's artifact travelling the same road.
  late DriveStateProtection publicDrive;

  DriveStateProtection protectionFor(SecretKey key) =>
      DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.private,
        driveKey: key,
      ).protection!;

  /// The producer: a drive with rows in it, which is what gets exported.
  late Database producerDb;

  /// The consumer: the database the artifact is merged into.
  late Database db;
  late DriveStateImporter importer;

  setUpAll(() async {
    // Producer and consumer are two databases on purpose - an artifact is
    // written by one client and read by another - and drift's warning about
    // that is noise here, not a race.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    owner = await Wallet.generate();
    ownerAddress = await owner.getAddress();
    driveKey = await aesGcm.newSecretKey();
    privateDrive = protectionFor(driveKey);
    publicDrive = DriveStateProtection.forDrive(
      privacy: DrivePrivacyTag.public,
      driveKey: null,
    ).protection!;
  });

  /// The artifact as it reaches the importer: the transaction's data, and the
  /// tags an indexer reported for it.
  ///
  /// Every tag is a parameter because half of these tests are about a tag
  /// disagreeing with the body it describes.
  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      sealArtifact(
    Uint8List payload, {
    String taggedDriveId = driveId,
    required int blockEnd,
    int blockStart = 0,
    int? entityCount,
    String? stateVersion,
    String? cipher,
    SecretKey? key,

    /// How the body is sealed. Defaults to the private chain, which is what
    /// almost every test here is about; the public-drive tests pass
    /// [publicDrive] and get a body with no cipher around it.
    DriveStateProtection? protection,

    /// Whether the `Cipher` / `Cipher-IV` tags are written. `null` follows
    /// what was actually sealed, which is the only combination a real
    /// producer can publish. Setting it apart from the body is how a test
    /// builds the artifact the cipher/privacy cross-check exists for.
    bool? withCipherTags,
    bool omitCipherTag = false,
    bool omitCipherIvTag = false,

    /// A `Cipher-IV` tag value of the test's choosing, for the cases where
    /// what matters is that nothing ever reads it.
    String? cipherIvTag,

    /// No `State-Version` tag at all. Distinct from a null [stateVersion],
    /// which means "whatever a correct producer would write".
    bool omitStateVersionTag = false,
    Wallet? signer,

    /// What the *payload* claims about its own coverage, which is the half of
    /// the claim the owner signs. It defaults to whatever the tags say,
    /// because that is the only combination a real producer can publish: the
    /// tags are derived from the signed claim. Setting it apart from the tags
    /// is how a test builds the artifact this check exists for.
    Map<String, dynamic>? signedCoverage,

    /// A payload with no coverage claim at all - what a producer that predated
    /// the field would have written, if one had ever published.
    bool omitSignedCoverage = false,

    /// Bytes that are not a drive state container at all. Nothing can be
    /// written into them, so the coverage claim and the entity count are the
    /// caller's to state.
    bool payloadIsOpaque = false,
  }) async {
    if (!payloadIsOpaque) {
      if (omitSignedCoverage) {
        // `meta` is one row of NOT NULL columns, so "a payload with no
        // coverage claim" has no expression inside this container. The
        // nearest a producer could publish is a payload with no `meta` row at
        // all, and the reader then refuses it before it can compare a claim
        // it never found - a coarser refusal than the JSON container's
        // `coverageMismatch`, and the honest one here.
        payload = editArtifact(payload, ['DELETE FROM meta']);
      } else {
        final coverage =
            signedCoverage ?? {'blockStart': blockStart, 'blockEnd': blockEnd};
        payload = editArtifact(payload, [
          'UPDATE meta SET blockStart = ${coverage['blockStart']}, '
          'blockEnd = ${coverage['blockEnd']}',
        ]);
      }
    }

    final sealed = await codec.seal(
      plaintext: payload,
      protection:
          protection ?? (key == null ? privateDrive : protectionFor(key)),
      wallet: signer ?? owner,
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
          EntityTag.driveId: taggedDriveId,
          EntityTag.driveStateId: 'drive-state-id',
          if (!omitStateVersionTag)
            EntityTag.stateVersion: stateVersion ?? currentVersionString,
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '$blockStart',
          EntityTag.blockEnd: '$blockEnd',
          EntityTag.entityCount: '${entityCount ?? entitiesIn(payload)}',
          if ((withCipherTags ?? envelope.isEncrypted) && !omitCipherTag)
            EntityTag.cipher: cipher ?? Cipher.aes256,
          if ((withCipherTags ?? envelope.isEncrypted) && !omitCipherIvTag)
            EntityTag.cipherIv: cipherIvTag ??
                envelope.cipherIvAsBase64 ??
                // A syntactically valid base64 nonce for the cases that put a
                // cipher tag on a body that has none. Nothing reads it: the
                // cross-check refuses the artifact first.
                'AAAAAAAAAAAAAAAA',
        },
        minedAtHeight: blockEnd,
      ),
      body: envelope.body,
    );
  }

  /// The producer's artifact: a real SQLite database, built the way the
  /// producer builds one, so a test can reach into it with SQL and make one
  /// field disagree with its tags.
  ///
  /// `blockEnd` is 0 here and is written afterwards by [sealArtifact], which
  /// is the layer that knows what coverage a given test wants the payload to
  /// claim.
  Future<Uint8List> exportedPayload([String id = driveId]) async {
    final artifact = await sqlite.exportDriveState(
      producerDb,
      driveId: id,
      sink: await createArtifactSink('import-test'),
      blockEnd: 0,
    );
    return artifact.bytes;
  }

  /// Attaches a drive to the consumer, the way a client that is about to sync
  /// one already has it: a row, its key material, and nothing synced yet.
  Future<void> attachDrive(
    Database into, {
    String id = driveId,
    String rootFolder = rootFolderId,
    String name = 'stale-local-name',
    int? lastBlockHeight,
    DateTime? lastUpdated,
    String privacy = DrivePrivacyTag.private,
  }) {
    final isPrivate = privacy == DrivePrivacyTag.private;

    return into.into(into.drives).insert(
          DrivesCompanion.insert(
            id: id,
            rootFolderId: rootFolder,
            ownerAddress: ownerAddress,
            name: name,
            privacy: privacy,
            // A public drive has none of this, which is exactly why
            // `DriveDao.getDriveKey` returns null for one.
            encryptedKey: isPrivate
                ? Value(Uint8List.fromList([1, 2, 3, 4]))
                : const Value(null),
            keyEncryptionIv: isPrivate
                ? Value(Uint8List.fromList([5, 6, 7]))
                : const Value(null),
            driveKeyGenerated: Value(isPrivate),
            syncCursor: const Value('a-local-gateway-cursor'),
            lastBlockHeight: Value(lastBlockHeight ?? 0),
            lastUpdated: Value(lastUpdated ?? DateTime(2020)),
          ),
        );
  }

  /// Makes the producer's drive public, so the payload it exports says so.
  Future<void> publishAsPublicDrive() =>
      producerDb.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
      ));

  Future<Drive> driveRow(Database from, [String id = driveId]) =>
      (from.select(from.drives)..where((d) => d.id.equals(id))).getSingle();

  Future<List<FileEntry>> fileRows(Database from, [String id = driveId]) =>
      (from.select(from.fileEntries)..where((f) => f.driveId.equals(id))).get();

  Future<List<FolderEntry>> folderRows(Database from, [String id = driveId]) =>
      (from.select(from.folderEntries)..where((f) => f.driveId.equals(id)))
          .get();

  setUp(() async {
    producerDb = getTestDb();
    db = getTestDb();
    importer = DriveStateImporter(db.driveDao, codec: codec);

    await addTestFilesToDb(
      producerDb,
      driveId: driveId,
      rootFolderId: rootFolderId,
      nestedFolderId: nestedFolderId,
      emptyNestedFolderCount: 1,
      emptyNestedFolderIdPrefix: 'empty-nested-folder-id',
      rootFolderFileCount: 2,
      nestedFolderFileCount: 1,
    );
    // The producer publishes a drive it has actually synced: the export
    // carries only rows a revision vouches for, and `addTestFilesToDb` writes
    // revisions for its files but not for its folders.
    await addFolderRevisionsToDb(
      producerDb,
      driveId: driveId,
      folderIds: [rootFolderId, nestedFolderId, 'empty-nested-folder-id0'],
    );
    // The producer owns the drive it publishes, and is far ahead of the
    // consumer. The watermark tests turn on that number never travelling.
    await producerDb.driveDao.writeToDrive(
      DrivesCompanion(
        id: const Value(driveId),
        ownerAddress: Value(ownerAddress),
        privacy: const Value(DrivePrivacyTag.private),
        lastBlockHeight: const Value(1814228),
        syncCursor: const Value('a-producer-gateway-cursor'),
        lastUpdated: Value(DateTime(2024, 6, 1)),
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await producerDb.close();
  });

  group('a good artifact', () {
    test('lands the drive\'s rows and takes its watermark from Block-End',
        () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.foldersWritten, 3);
      expect(result.stats!.filesWritten, 3);
      expect(result.stats!.rowsKeptLocallyNewer, 0);

      expect(await folderRows(db), hasLength(3));
      expect(await fileRows(db), hasLength(3));
      expect(
        (await folderRows(db)).map((f) => f.id),
        containsAll(<String>[rootFolderId, nestedFolderId]),
      );

      final drive = await driveRow(db);
      expect(drive.lastBlockHeight, 900);
      expect(result.stats!.watermark, 900);
      // The producer's own watermark is 1814228 and its cursor is its
      // gateway's. Neither is in the payload, and neither may be adopted.
      expect(drive.syncCursor, 'a-local-gateway-cursor');
    });

    test('leaves the drive key exactly where it was', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      final drive = await driveRow(db);
      expect(drive.encryptedKey, Uint8List.fromList([1, 2, 3, 4]));
      expect(drive.keyEncryptionIv, Uint8List.fromList([5, 6, 7]));
      expect(drive.driveKeyGenerated, isTrue);
      expect(drive.privacy, DrivePrivacyTag.private);
    });

    test('updates the drive row it already had', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect((await driveRow(db)).name, 'fake-drive-name');
    });

    test('reports what it did, for the log §7 asks for', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.detail, contains('imported=6'));
      expect(result.detail, contains('watermark=900'));
      expect(result.detail, contains('parse='));
      expect(result.detail, contains('merge='));
      expect(
        DriveStateOutcomeReporter.formatLine(
          driveId: driveId,
          outcome: result.outcome,
          detail: result.detail,
        ),
        allOf(contains('artifact used'), contains('outcome=used')),
      );
    });
  });

  /// The half of the payload the file list cannot render without, and the
  /// table that is rebuilt rather than carried. `drive_state_round_trip_test`
  /// asserts the consequence through `watchFolderContents`; these assert the
  /// rows and the derivation.
  group('revisions, licences, and the transactions derived from them', () {
    Future<List<FileRevision>> fileRevisionRows([String id = driveId]) =>
        (db.select(db.fileRevisions)..where((r) => r.driveId.equals(id))).get();

    Future<List<NetworkTransaction>> transactionRows() =>
        db.select(db.networkTransactions).get();

    test('lands the revisions behind every entry it imported', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(await fileRevisionRows(), hasLength(3));
      expect(
        (await fileRevisionRows()).map((r) => r.fileId).toSet(),
        (await fileRows(db)).map((f) => f.id).toSet(),
      );
      expect(
        await (db.select(db.folderRevisions)
              ..where((r) => r.driveId.equals(driveId)))
            .get(),
        hasLength(3),
      );
    });

    /// The table that is not on the wire. Every transaction the imported
    /// revisions name has to have a row, because the file list reaches
    /// `network_transactions` through an INNER JOIN and a missing row drops
    /// the file.
    test('regenerates a network transaction for every id the revisions name',
        () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      final known = (await transactionRows()).map((t) => t.id).toSet();
      for (final revision in await fileRevisionRows()) {
        expect(known, contains(revision.metadataTxId));
        expect(known, contains(revision.dataTxId));
      }
      for (final revision in await (db.select(db.folderRevisions)
            ..where((r) => r.driveId.equals(driveId)))
          .get()) {
        expect(known, contains(revision.metadataTxId));
      }
    });

    /// The sync helpers mark a file's data transaction `pending`, because
    /// sync writes a revision the moment it reads the metadata and the data
    /// may not be mined yet. An artifact is not that situation: its coverage
    /// claim is the producer's own synced watermark. Importing these as
    /// pending would paint every file in a restored drive with the pending
    /// icon *and* queue a per-transaction confirmation query for each one —
    /// 42,000 of them on the drive this feature was measured against, which
    /// is exactly the work the artifact exists to avoid.
    test('marks the regenerated transactions as mined, not pending', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(await transactionRows(), isNotEmpty);
      for (final tx in await transactionRows()) {
        expect(tx.status, TransactionStatus.confirmed, reason: tx.id);
      }
      expect(await db.driveDao.pendingTransactions().get(), isEmpty);
    });

    /// A status this client established for itself is not the artifact's to
    /// overwrite. `network_transactions` is derived local state, not a
    /// published fact, so the import may only add rows.
    test('never overwrites a transaction status the client already had',
        () async {
      await attachDrive(db);
      final payload = await exportedPayload();

      // The consumer already knows one of the artifact's data transactions,
      // and knows it failed.
      final failedTxId = artifactValue(
        payload,
        'SELECT dataTxId FROM file_revisions ORDER BY fileId LIMIT 1',
      )! as String;

      await db.into(db.networkTransactions).insert(
            NetworkTransactionsCompanion.insert(
              id: failedTxId,
              status: const Value(TransactionStatus.failed),
            ),
          );

      final artifact = await sealArtifact(payload, blockEnd: 900);
      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      final kept = (await transactionRows()).firstWhere(
        (t) => t.id == failedTxId,
      );
      expect(kept.status, TransactionStatus.failed);
    });

    test('reports what it landed, beside the entities', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      // 3 file revisions + 3 folder revisions.
      expect(result.stats!.revisionsWritten, 6);
      expect(result.detail, contains('revisions=6'));
      expect(result.detail, contains('transactions='));
      // Entities are still entities: the count the `Entity-Count` tag is
      // checked against does not move because revisions travel.
      expect(result.stats!.entitiesImported, 6);
      expect(result.detail, contains('imported=6'));
    });

    test('adds a revision the client lacks and leaves the ones it has',
        () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );
      final afterFirst = await fileRevisionRows();

      // The same artifact again, on a drive that now holds all of it: a
      // revision's primary key contains its `dateCreated`, so there is
      // nothing to overwrite and nothing to duplicate.
      final second = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(second.outcome, DriveStateOutcome.used, reason: second.detail);
      expect(await fileRevisionRows(), hasLength(afterFirst.length));
      expect(second.stats!.revisionsWritten, 0);
    });

    /// Same primary key, different content. A revision is keyed by
    /// `(fileId, driveId, dateCreated)`, so this is the artifact and the
    /// client disagreeing about one row rather than the artifact carrying a
    /// newer one — and the client's own row is the one that stands, which is
    /// the merge policy the entry sections state and this one inherits.
    test('leaves a revision the client already holds exactly as it was',
        () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      final published = artifactRow(
        payload,
        'SELECT * FROM file_revisions ORDER BY fileId LIMIT 1',
      );

      await db.into(db.fileRevisions).insert(
            FileRevisionsCompanion.insert(
              fileId: published['fileId']! as String,
              driveId: driveId,
              parentFolderId: published['parentFolderId']! as String,
              name: 'what-this-client-recorded',
              metadataTxId: published['metadataTxId']! as String,
              dataTxId: published['dataTxId']! as String,
              action: RevisionAction.create,
              size: published['size']! as int,
              lastModifiedDate: artifactDate(published['lastModifiedDate']),
              dateCreated: Value(artifactDate(published['dateCreated'])),
            ),
          );

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      final kept = (await fileRevisionRows())
          .firstWhere((r) => r.fileId == published['fileId']);
      expect(kept.name, 'what-this-client-recorded');
      // And the artifact's other revisions still landed.
      expect(await fileRevisionRows(), hasLength(3));
    });

    test('leaves a licence the client already holds exactly as it was',
        () async {
      await attachDrive(db);

      // The producer publishes a licence on one of its files.
      final licensedFileId =
          (await producerDb.select(producerDb.fileRevisions).get())
              .first
              .fileId;
      await producerDb.into(producerDb.licenses).insert(
            LicensesCompanion.insert(
              fileId: licensedFileId,
              driveId: driveId,
              dataTxId: 'a-data-tx',
              licenseTxType: 'assertion',
              licenseTxId: 'a-license-tx',
              licenseType: 'udl',
            ),
          );

      // The consumer already has the row, and calls it something else.
      await db.into(db.licenses).insert(
            LicensesCompanion.insert(
              fileId: licensedFileId,
              driveId: driveId,
              dataTxId: 'a-data-tx',
              licenseTxType: 'assertion',
              licenseTxId: 'a-license-tx',
              licenseType: 'what-this-client-recorded',
            ),
          );

      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(
        (await db.select(db.licenses).get()).single.licenseType,
        'what-this-client-recorded',
      );
    });

    test('rejects a payload whose revisions belong to another drive', () async {
      await attachDrive(db);
      final payload = editArtifact(await exportedPayload(), [
        "UPDATE file_revisions SET driveId = '$otherDriveId' "
            'WHERE rowid = (SELECT MIN(rowid) FROM file_revisions)',
      ]);

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains(otherDriveId));
      expect(await fileRevisionRows(), isEmpty);
      expect(await fileRows(db), isEmpty);
    });

    test('rejects a payload whose licences belong to another drive', () async {
      await attachDrive(db);
      // The producer has no licences, so put one there to be rejected.
      final payload = editArtifact(await exportedPayload(), [
        'INSERT INTO licenses (fileId, driveId, dataTxId, licenseTxType, '
            'licenseTxId, bundledIn, dateCreated, licenseType, customGQLTags) '
            "VALUES ('a-file', '$otherDriveId', 'a-data-tx', 'assertion', "
            "'a-license-tx', NULL, 1000, 'udl', NULL)",
      ]);

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains(otherDriveId));
      expect(await db.select(db.licenses).get(), isEmpty);
    });
  });

  group('merging, not replacing', () {
    test('does not clobber a row the database holds a newer copy of', () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      final artifactFile = artifactRow(
        payload,
        'SELECT id, lastUpdated FROM file_entries ORDER BY id LIMIT 1',
      );
      final contestedId = artifactFile['id']! as String;
      final afterTheArtifact = artifactDate(artifactFile['lastUpdated'])
          .add(const Duration(days: 1));

      // Renamed locally after the artifact was published - the ordinary case
      // of a client that has done work the producer had not seen.
      await db.into(db.fileEntries).insert(
            FileEntriesCompanion.insert(
              id: contestedId,
              driveId: driveId,
              parentFolderId: rootFolderId,
              name: 'renamed-locally',
              dataTxId: 'local-data-tx',
              size: 4242,
              path: '',
              lastModifiedDate: afterTheArtifact,
              lastUpdated: Value(afterTheArtifact),
            ),
          );

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.rowsKeptLocallyNewer, 1);
      expect(result.stats!.filesWritten, 2);

      final kept = (await fileRows(db)).firstWhere((f) => f.id == contestedId);
      expect(kept.name, 'renamed-locally');
      expect(kept.size, 4242);
      expect(kept.dataTxId, 'local-data-tx');
      // The rows the artifact did know better about still landed.
      expect(await fileRows(db), hasLength(3));
    });

    test('keeps a local row the artifact has never heard of', () async {
      await attachDrive(db);
      await db.into(db.fileEntries).insert(
            FileEntriesCompanion.insert(
              id: 'uploaded-after-the-artifact',
              driveId: driveId,
              parentFolderId: rootFolderId,
              name: 'newer-than-the-artifact',
              dataTxId: 'data-tx',
              size: 1,
              path: '',
              lastModifiedDate: DateTime(2025, 1, 1),
            ),
          );

      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(await fileRows(db), hasLength(4));
      expect(
        (await fileRows(db)).map((f) => f.id),
        contains('uploaded-after-the-artifact'),
      );
    });

    test('touches no other drive', () async {
      await attachDrive(db);
      await addTestFilesToDb(
        db,
        driveId: otherDriveId,
        rootFolderId: 'other-root-folder-id',
        nestedFolderId: 'other-nested-folder-id',
        emptyNestedFolderCount: 1,
        emptyNestedFolderIdPrefix: 'other-empty-',
        rootFolderFileCount: 2,
        nestedFolderFileCount: 1,
      );
      await db.driveDao.writeToDrive(
        const DrivesCompanion(
          id: Value(otherDriveId),
          lastBlockHeight: Value(4242),
          syncCursor: Value('the-other-drive-cursor'),
        ),
      );

      final before = await fileRows(db, otherDriveId);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(await fileRows(db, otherDriveId), equals(before));
      expect(await folderRows(db, otherDriveId), hasLength(3));

      final untouched = await driveRow(db, otherDriveId);
      expect(untouched.lastBlockHeight, 4242);
      expect(untouched.syncCursor, 'the-other-drive-cursor');
      expect(untouched.name, 'fake-drive-name');
    });
  });

  /// A drive is a tree, and the merge has to leave one behind.
  ///
  /// The export publishes only rows a revision vouches for, and a ghost folder
  /// has none - that is what makes it a ghost. Its *files* do, so they travel
  /// and their parent does not. Nothing in the app lists a file except by its
  /// parent, and the import advances the watermark past the range whose
  /// metadata would have re-derived the ghost, so an unresolved parent is a
  /// permanently invisible file rather than a temporarily misplaced one.
  group('the row graph', () {
    /// Removes a folder's revision, leaving its entry row behind: a row the
    /// producer holds and nothing on chain vouches for, which is what a ghost
    /// and a root folder placeholder both are.
    Future<void> forgetFolderRevisions(List<String> folderIds) =>
        (producerDb.delete(producerDb.folderRevisions)
              ..where((r) => r.folderId.isIn(folderIds)))
            .go();

    /// Removes a folder from the producer entirely - its entry row and the
    /// revision behind it - so the artifact carries neither.
    ///
    /// The JSON export filtered `folder_entries` down to the rows a revision
    /// vouched for, so dropping the revision was enough to keep a folder out
    /// of a payload. The SQLite export copies the table whole, so a fixture
    /// that wants a folder absent from the artifact has to remove both. The
    /// case under test is unchanged: a file travels and its parent folder
    /// does not.
    Future<void> forgetFolders(List<String> folderIds) async {
      await forgetFolderRevisions(folderIds);
      await (producerDb.delete(producerDb.folderEntries)
            ..where((f) => f.id.isIn(folderIds)))
          .go();
    }

    Future<DriveStateImportResult> publishAndImport() async {
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      return importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );
    }

    Future<FolderEntry> folderRow(String id) =>
        (db.select(db.folderEntries)..where((f) => f.id.equals(id)))
            .getSingle();

    test('materialises the ghost a file\'s parent has become', () async {
      await forgetFolders([nestedFolderId]);
      await attachDrive(db);

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.foldersWritten, 2);
      expect(result.stats!.foldersMaterialised, 1);

      // The shape `SyncRepository.createGhosts` writes, so that the ghost UI
      // and its Fix flow work on it unchanged.
      final ghost = await folderRow(nestedFolderId);
      expect(ghost.isGhost, isTrue);
      expect(ghost.name, nestedFolderId);
      expect(ghost.parentFolderId, rootFolderId);

      // And the file inside it is reachable, which is the whole point.
      final contents = await db.driveDao
          .watchFolderContents(driveId, folderId: nestedFolderId)
          .first;
      expect(contents.files.map((f) => f.id), ['${nestedFolderId}0']);

      final root = await db.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first;
      expect(root.subfolders.map((f) => f.id), contains(nestedFolderId));
    });

    /// Closure is not acyclicity. Every `parentFolderId` resolving says every
    /// parent has a row, not that walking parents ever stops — and
    /// `DriveDao.getFolderTree` recurses on `parentFolderId` with no depth
    /// bound, so a loop hangs drive size, folder download, manifests and
    /// share-folder selection. It hangs them permanently: once
    /// `blockEnd == localWatermark` the same payload re-applies on every sync.
    ///
    /// Chain data cannot produce a cycle, so this is a guard against a
    /// malformed or broken producer — which is the case the threat model
    /// keeps, because an artifact is authentic, permanent and cannot be
    /// recalled.
    group('cycles', () {
      test('refuses a payload whose folders point at each other', () async {
        await producerDb.into(producerDb.folderEntries).insert(
              FolderEntriesCompanion.insert(
                id: 'loop-a',
                driveId: driveId,
                parentFolderId: const Value('loop-b'),
                name: 'loop-a',
                path: '',
              ),
            );
        await producerDb.into(producerDb.folderEntries).insert(
              FolderEntriesCompanion.insert(
                id: 'loop-b',
                driveId: driveId,
                parentFolderId: const Value('loop-a'),
                name: 'loop-b',
                path: '',
              ),
            );
        await addFolderRevisionsToDb(
          producerDb,
          driveId: driveId,
          folderIds: ['loop-a', 'loop-b'],
        );
        await attachDrive(db);

        final result = await publishAndImport();

        expect(result.outcome, DriveStateOutcome.integrityFailed);
        expect(result.detail, contains('cycle'));
        // Validate before write: nothing landed.
        expect(await db.select(db.folderEntries).get(), isEmpty);
      });

      /// The half that a payload-only check would miss. Neither row is a cycle
      /// by itself: the local folder is a perfectly ordinary child, and the
      /// carried row only re-parents one folder. The loop exists solely in the
      /// graph the merge would leave behind, which is the graph that has to be
      /// checked.
      test('refuses a loop it would close through a row already held',
          () async {
        await attachDrive(db);

        // Locally: nested sits under a folder that the payload is about to
        // re-parent underneath nested.
        await db.into(db.folderEntries).insert(
              FolderEntriesCompanion.insert(
                id: 'local-child',
                driveId: driveId,
                parentFolderId: const Value(nestedFolderId),
                name: 'local-child',
                path: '',
              ),
            );

        await (producerDb.update(producerDb.folderEntries)
              ..where((f) => f.id.equals(nestedFolderId)))
            .write(const FolderEntriesCompanion(
          parentFolderId: Value('local-child'),
        ));

        final result = await publishAndImport();

        expect(result.outcome, DriveStateOutcome.integrityFailed);
        expect(result.detail, contains('cycle'));
      });

      test('a deep chain that ends at the root is not a cycle', () async {
        var parent = rootFolderId;
        final chain = [for (var i = 0; i < 60; i++) 'deep-$i'];

        for (final id in chain) {
          await producerDb.into(producerDb.folderEntries).insert(
                FolderEntriesCompanion.insert(
                  id: id,
                  driveId: driveId,
                  parentFolderId: Value(parent),
                  name: id,
                  path: '',
                ),
              );
          parent = id;
        }
        await addFolderRevisionsToDb(
          producerDb,
          driveId: driveId,
          folderIds: chain,
        );
        await attachDrive(db);

        final result = await publishAndImport();

        expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
        expect((await folderRow('deep-59')).id, 'deep-59');
      });
    });

    test('materialises the ghost a folder\'s parent has become', () async {
      // A folder whose own parent is the ghost - the nesting case, and the one
      // no file reaches, so it is the folder section that has to be walked.
      await producerDb.into(producerDb.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: 'child-of-a-ghost',
              driveId: driveId,
              parentFolderId: const Value('a-folder-that-never-resolved'),
              name: 'child-of-a-ghost',
              path: '',
            ),
          );
      await addFolderRevisionsToDb(
        producerDb,
        driveId: driveId,
        folderIds: ['child-of-a-ghost'],
      );
      await attachDrive(db);

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.foldersMaterialised, 1);

      final ghost = await folderRow('a-folder-that-never-resolved');
      expect(ghost.isGhost, isTrue);
      expect(ghost.parentFolderId, rootFolderId);

      // A stand-in is parented at the root, never at another stand-in, so one
      // pass closes a chain of any depth.
      expect((await folderRow('child-of-a-ghost')).parentFolderId,
          'a-folder-that-never-resolved');
    });

    test('materialises nothing when every parent already resolves', () async {
      await attachDrive(db);

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.foldersMaterialised, 0);
    });

    test('keeps a local folder row that is newer and has a revision behind it',
        () async {
      await attachDrive(db);
      // Renamed locally after the artifact was published, and vouched for the
      // way a real rename vouches for itself. The stand-in rule must not reach
      // this row.
      await db.into(db.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: nestedFolderId,
              driveId: driveId,
              parentFolderId: const Value(rootFolderId),
              name: 'renamed-locally',
              path: '',
              lastUpdated: Value(DateTime(2030)),
            ),
          );
      await addFolderRevisionsToDb(
        db,
        driveId: driveId,
        folderIds: [nestedFolderId],
      );

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.rowsKeptLocallyNewer, 1);
      expect((await folderRow(nestedFolderId)).name, 'renamed-locally');
    });

    test('keeps a local stand-in the artifact does not vouch for either',
        () async {
      // The export never publishes a folder row without its revision, but an
      // importer checks what arrived rather than trusting the producer to have
      // run the filter. A payload that skipped it is offering a guess of its
      // own - possibly its *own* ghost, stamped `now` - and a guess does not
      // get to overrule this client's guess.
      //
      // Since the exporter now applies that filter, the offending payload has
      // to be built on purpose: drop the revision on the producer so the row
      // is genuinely unvouched, then put it back into the artifact by hand —
      // which is exactly what a producer that skipped the filter would ship.
      await forgetFolderRevisions([nestedFolderId]);

      await attachDrive(db);
      await db.into(db.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: nestedFolderId,
              driveId: driveId,
              parentFolderId: const Value(rootFolderId),
              name: nestedFolderId,
              path: '',
              isGhost: const Value(true),
              lastUpdated: Value(DateTime(2030)),
            ),
          );

      final payload = editArtifact(await exportedPayload(), [
        // The row the filter correctly withheld, put back.
        'INSERT OR REPLACE INTO folder_entries '
            '(id, driveId, name, parentFolderId, path, dateCreated, '
            'lastUpdated, isGhost, isHidden) '
            "VALUES ('$nestedFolderId', '$driveId', '$nestedFolderId', "
            "'$rootFolderId', '', 1700000000, 1700000000, 1, 0)",
      ]);

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.rowsKeptLocallyNewer, 1);
      expect((await folderRow(nestedFolderId)).isGhost, isTrue);
    });

    test('refuses a payload naming a root folder nothing can resolve',
        () async {
      // Reachable from a broken producer - a drive whose root folder metadata
      // never resolved has a placeholder row, which the export's chain-derived
      // filter drops - and trivially from a hostile one, since an artifact is
      // authentic, signed and permanent.
      await producerDb.driveDao.writeToDrive(
        const DrivesCompanion(
          id: Value(driveId),
          rootFolderId: Value('a-folder-that-is-in-no-section'),
        ),
      );
      await attachDrive(db);

      final result = await publishAndImport();

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('a-folder-that-is-in-no-section'));
      // Refused before the first write, like every other rejection: a partial
      // import is worse than none.
      expect(await folderRows(db), isEmpty);
      expect(await fileRows(db), isEmpty);
      expect((await driveRow(db)).lastBlockHeight, 0);
      expect((await driveRow(db)).rootFolderId, rootFolderId);
    });

    test('imports when the root folder is only in the local database',
        () async {
      // The producer's root folder metadata never resolved, so the payload
      // cannot carry it - but the consumer attached this drive and holds
      // `DriveDao._rootFolderPlaceholder`'s row for it. Nothing is missing.
      await forgetFolders([rootFolderId]);
      await attachDrive(db);
      await db.into(db.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: rootFolderId,
              driveId: driveId,
              name: 'stale-local-name',
              path: '',
            ),
          );

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.foldersMaterialised, 0);
    });

    test('materialises the root folder the drive is keeping, if it must',
        () async {
      // Nothing carries the root and nothing local holds it, but the drive is
      // keeping its own `rootFolderId` rather than adopting the payload's - so
      // there is no claim to refuse, and a stand-in parented at a root that
      // does not exist would be an orphan of the kind it was written to fix.
      await forgetFolders(
        [rootFolderId, nestedFolderId, 'empty-nested-folder-id0'],
      );
      await (producerDb.delete(producerDb.fileEntries)
            ..where((f) => f.parentFolderId.equals(rootFolderId)))
          .go();
      await (producerDb.delete(producerDb.fileRevisions)
            ..where((r) => r.parentFolderId.equals(rootFolderId)))
          .go();
      // Newer than the payload's drive row, so its metadata is not adopted.
      await attachDrive(db, lastUpdated: DateTime(2025));

      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.foldersMaterialised, 2);

      final root = await folderRow(rootFolderId);
      expect(root.parentFolderId, null);
      expect(root.isGhost, isFalse);
      expect((await folderRow(nestedFolderId)).parentFolderId, rootFolderId);

      // The drive opens, which is what a root folder row is for.
      final contents = await db.driveDao.watchFolderContents(driveId).first;
      expect(contents.folder.id, rootFolderId);
    });
  });

  /// The cipher/privacy cross-check, in both directions, and the payload's own
  /// `privacy` field checked against the same trustworthy value.
  ///
  /// The shape is the one `Block-Start`/`Block-End` already has: an untrusted
  /// claim - here the transaction's cipher tags, chosen by whoever posted it -
  /// checked against something the reader knows for itself. None of these
  /// artifacts is damaged; each opens perfectly for the drive it was made for.
  group('the cipher must match the privacy of the drive it is for', () {
    test('a public drive imports an artifact with no cipher tags', () async {
      await publishAsPublicDrive();
      await attachDrive(db, privacy: DrivePrivacyTag.public);

      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: publicDrive,
      );

      // Neither tag on the transaction at all - the discriminator.
      expect(artifact.candidate.tags.containsKey(EntityTag.cipher), isFalse);
      expect(artifact.candidate.tags.containsKey(EntityTag.cipherIv), isFalse);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: publicDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(await fileRows(db), isNotEmpty);
      expect((await driveRow(db)).lastBlockHeight, 900);
      expect((await driveRow(db)).privacy, DrivePrivacyTag.public);
    });

    test('a private drive refuses an artifact with no cipher tags', () async {
      await attachDrive(db);

      // Genuine bytes: the owner's own export, signed by the owner, and
      // readable. What is wrong is that a private drive's artifact was
      // produced without its cipher - the one thing this format must never
      // accept, because accepting it normalises publishing a private drive's
      // entire structure in the clear.
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: publicDrive,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      expect(result.detail, contains('never published in the clear'));
      expect(await fileRows(db), isEmpty);
      expect(await folderRows(db), isEmpty);
      expect((await driveRow(db)).lastBlockHeight, 0);
    });

    test('a public drive refuses an artifact that declares a cipher', () async {
      await publishAsPublicDrive();
      await attachDrive(db, privacy: DrivePrivacyTag.public);

      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: privateDrive,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: publicDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      // Not `decryptFailed`: nothing was attempted with a key this reader
      // never had, and reporting one would send a reader after the wrong bug.
      expect(result.outcome, isNot(DriveStateOutcome.decryptFailed));
      expect(await fileRows(db), isEmpty);
      expect((await driveRow(db)).lastBlockHeight, 0);
    });

    test('the tags are checked before the Cipher-IV is even decoded', () async {
      // The importer's own half of the cross-check, and the case that shows it
      // is not merely a faster copy of the codec's. A public drive is offered
      // an artifact whose `Cipher` tag is present and whose `Cipher-IV` is not
      // base64 at all. Read in the other order, the answer is "the Cipher-IV
      // tag is not base64" - a sentence about a malformed tag, when what is
      // actually wrong is that this artifact is for a drive of the other
      // privacy and its IV was never going to matter.
      await publishAsPublicDrive();
      await attachDrive(db, privacy: DrivePrivacyTag.public);

      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: publicDrive,
        withCipherTags: true,
        cipherIvTag: 'not base64 at all !!!',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: publicDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      expect(result.detail, isNot(contains('base64')));
      // And the detail is the importer's, not the codec's: it names the drive
      // and the transaction, which is what a reader of a sync log needs and
      // what the codec - which sees neither - cannot say.
      expect(result.detail, contains(driveId));
      expect(result.detail, contains(artifact.candidate.txId));
    });

    test('a private drive is told which drive and which transaction', () async {
      await attachDrive(db);

      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: publicDrive,
        // Tagged as encrypted while the body is not, so the importer's tag
        // check sees a cipher the codec's check would never be handed. Only
        // the tag-level check can catch this before the envelope is built.
        withCipherTags: true,
        cipherIvTag: 'also not base64 !!!',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      // The tags say encrypted and the drive is private, so the tag-level
      // check passes - and the codec then finds the body is not encrypted at
      // all. Which is a privacy mismatch too, arrived at one layer in.
      expect(result.outcome, isNot(DriveStateOutcome.used));
      expect(await fileRows(db), isEmpty);
    });

    test('the tags are checked before the body is opened at all', () async {
      await attachDrive(db);

      // A body that is not a data item, is not signed, and is not even long
      // enough to be either. If the cross-check ran later this would come
      // back as an integrity or signature failure; that it does not is what
      // says a plaintext body for a private drive is never parsed.
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: publicDrive,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: Uint8List.fromList([1, 2, 3]),
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
    });

    test(
        'a payload whose own privacy disagrees with the local drive is '
        'refused', () async {
      // The third check, one layer in: `_driveCompanion` copies the payload's
      // `privacy` onto the local drive row, so a payload claiming `public`
      // for a private drive would relabel the user's own drive while its key
      // material sat untouched beside it.
      //
      // Sealed the private way, so the tag-level cross-check passes and this
      // is the only thing that can catch it.
      await attachDrive(db);
      await publishAsPublicDrive();

      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: privateDrive,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      expect(result.detail, contains('public'));
      expect(result.detail, contains('private'));
      expect(await fileRows(db), isEmpty);
      expect((await driveRow(db)).privacy, DrivePrivacyTag.private);
    });

    test('and in the other direction, for a public drive', () async {
      await attachDrive(db, privacy: DrivePrivacyTag.public);

      // The producer's drive is still private, so the payload says `private`
      // while the consumer holds the drive as public.
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        protection: publicDrive,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: publicDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.privacyMismatch);
      expect(await fileRows(db), isEmpty);
      expect((await driveRow(db)).privacy, DrivePrivacyTag.public);
    });
  });

  group('validation, before anything is written', () {
    /// Every rejection test asserts this, because a partial import is worse
    /// than none: the drive would carry rows from an artifact nobody trusted,
    /// and a watermark saying it need not look again.
    Future<void> expectNothingWritten() async {
      expect(await folderRows(db), isEmpty);
      expect(await fileRows(db), isEmpty);

      final drive = await driveRow(db);
      expect(drive.lastBlockHeight, 0);
      expect(drive.name, 'stale-local-name');
      expect(drive.syncCursor, 'a-local-gateway-cursor');
    }

    test('rejects an Entity-Count that disagrees with the payload', () async {
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        entityCount: 99,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.countMismatch);
      expect(result.detail, contains('99'));
      await expectNothingWritten();
    });

    test('rejects a payload for a different drive than the Drive-Id tag',
        () async {
      await attachDrive(db);
      final payload = editArtifact(await exportedPayload(), [
        "UPDATE drives SET id = 'a-completely-other-drive'",
      ]);

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('a-completely-other-drive'));
      await expectNothingWritten();
    });

    test('rejects a payload carrying a row that belongs to another drive',
        () async {
      await attachDrive(db);
      final payload = editArtifact(await exportedPayload(), [
        "UPDATE file_entries SET driveId = '$otherDriveId' "
            'WHERE rowid = (SELECT MIN(rowid) FROM file_entries)',
      ]);

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains(otherDriveId));
      await expectNothingWritten();
    });

    test('rejects a payload whose owner is not the one it verified against',
        () async {
      await attachDrive(db);
      final payload = editArtifact(await exportedPayload(), [
        "UPDATE drives SET ownerAddress = 'someone-else'",
      ]);

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('someone-else'));
      await expectNothingWritten();
    });

    /// The same candidate with different tags over the same body: an
    /// attacker's whole toolkit, since the bytes are not theirs to change.
    DriveStateArtifactCandidate retagged(
      DriveStateArtifactCandidate candidate,
      Map<String, String> tags,
    ) =>
        DriveStateArtifactCandidate(
          txId: candidate.txId,
          ownerAddress: candidate.ownerAddress,
          tags: {...candidate.tags, ...tags},
          minedAtHeight: candidate.minedAtHeight,
        );

    test(
        'rejects a Block-End tag that disagrees with the coverage the payload '
        'signed', () async {
      // The attack the signed coverage claim exists for, end to end. A third
      // party copies the owner's artifact bytes verbatim - they cannot forge
      // them, so they do not try - re-publishes them under their own wallet
      // with every tag copied except Block-End, and points a name at it. The
      // signature verifies, because these are the owner's bytes. The drive
      // decrypts, the Drive-Id matches, the Entity-Count matches. Only the
      // coverage is a lie, and if it were believed the drive's watermark
      // would jump to a height nothing was ever synced to and that range
      // would never be queried again.
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: retagged(
          artifact.candidate,
          {EntityTag.blockEnd: '9999999'},
        ),
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.coverageMismatch);
      expect(result.detail, contains('9999999'));
      expect(result.detail, contains('900'));
      await expectNothingWritten();

      // The same bytes, under the tags their owner published: accepted. So
      // what was rejected above was the tag, and nothing about the artifact.
      final honest = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(honest.outcome, DriveStateOutcome.used, reason: honest.detail);
      expect((await driveRow(db)).lastBlockHeight, 900);
    });

    test('rejects a Block-Start tag that hides the gap the payload declares',
        () async {
      // The other end of the same claim, and the same prize: an artifact that
      // genuinely covers [700, 900] moves the watermark nowhere for a client
      // synced to 500, because of the gap. Re-tagged as starting at 0, it
      // would move the watermark to 900 across 200 blocks nobody read.
      await attachDrive(db, lastBlockHeight: 500);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockStart: 700,
        blockEnd: 900,
      );

      final result = await importer.import(
        candidate: retagged(artifact.candidate, {EntityTag.blockStart: '0'}),
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.coverageMismatch);
      expect(await folderRows(db), isEmpty);
      expect(await fileRows(db), isEmpty);
      expect((await driveRow(db)).lastBlockHeight, 500);
    });

    test('rejects an absent Block-Start tag against a payload that has one',
        () async {
      // A missing tag reads as 0, which is what every v1 artifact publishes.
      // A payload claiming otherwise is refused rather than met half way.
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockStart: 700,
        blockEnd: 900,
      );
      final tags = Map<String, String>.from(artifact.candidate.tags)
        ..remove(EntityTag.blockStart);

      final result = await importer.import(
        candidate: DriveStateArtifactCandidate(
          txId: artifact.candidate.txId,
          ownerAddress: ownerAddress,
          tags: tags,
        ),
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.coverageMismatch);
      await expectNothingWritten();
    });

    test('rejects a payload that makes no coverage claim at all', () async {
      // There is no artifact on chain that predates the claim, so a payload
      // without one is not an old producer to accommodate. Falling back to
      // the tag would be reinstating exactly what the claim replaced.
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        omitSignedCoverage: true,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      await expectNothingWritten();
    });

    test('takes the watermark from the signed claim, not from the tag',
        () async {
      // Belt and braces on the check above: even if the two were somehow
      // allowed to differ, the value that reaches the database is the signed
      // one. The tag here agrees, so this is about provenance rather than
      // rejection.
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        signedCoverage: {'blockStart': 0, 'blockEnd': 900},
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(result.stats!.watermark, 900);
      expect((await driveRow(db)).lastBlockHeight, 900);
    });

    test('is a no-op for an artifact older than the drive\'s watermark',
        () async {
      await attachDrive(db, lastBlockHeight: 1000);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.rangeAlreadyCovered);
      expect(await folderRows(db), isEmpty);
      expect(await fileRows(db), isEmpty);
      // Never a regression: the watermark stays where it was.
      expect((await driveRow(db)).lastBlockHeight, 1000);
    });

    test('imports an artifact covering exactly what is already synced',
        () async {
      // The same range can still hold entities a sync skipped, so equal
      // coverage is not the no-op case.
      await attachDrive(db, lastBlockHeight: 900);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(await fileRows(db), hasLength(3));
    });

    test(
        'merges an artifact starting above the watermark without jumping the '
        'gap', () async {
      // Block-Start is 0 for every artifact this client publishes, but the
      // format allows an incremental one. Adopting its Block-End would move
      // the watermark over a range nobody synced.
      await attachDrive(db, lastBlockHeight: 500);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockStart: 700,
        blockEnd: 900,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);
      expect(await fileRows(db), hasLength(3));
      expect(result.stats!.watermark, 500);
      expect((await driveRow(db)).lastBlockHeight, 500);
    });
  });

  group('every failure is an outcome, never a throw', () {
    test('a drive key that does not open the body', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: protectionFor(await aesGcm.newSecretKey()),
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.decryptFailed);
      expect(await fileRows(db), isEmpty);
    });

    test('a body that arrived damaged', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      final damaged = Uint8List.fromList(artifact.body);
      damaged[damaged.length ~/ 2] ^= 0xff;

      final result = await importer.import(
        candidate: artifact.candidate,
        body: damaged,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.decryptFailed);
    });

    test('an artifact signed by someone other than the drive owner', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: 'not-the-owner',
      );

      expect(result.outcome, DriveStateOutcome.signatureFailed);
      expect(await fileRows(db), isEmpty);
    });

    test('a State-Version tagged with a newer major', () async {
      await attachDrive(db);
      final payload = editArtifact(
        await exportedPayload(),
        ["UPDATE meta SET version = '9.0'"],
      );
      final artifact = await sealArtifact(
        payload,
        blockEnd: 900,
        stateVersion: '9.0',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
      expect(result.detail, contains('newer'));
    });

    test('a State-Version tagged with an older major says so itself', () async {
      // The arm §6.1 is about. Without it, what an older major meets depends
      // on the payload's shape rather than on its version: refused for the
      // wrong reason if it happens to lack a section, and not refused at all
      // if it does not.
      await attachDrive(db);
      final payload = editArtifact(
        await exportedPayload(),
        ["UPDATE meta SET version = '0.0'"],
      );
      final artifact = await sealArtifact(
        payload,
        blockEnd: 900,
        stateVersion: '0.0',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
      expect(result.detail, contains('predates'));
      expect(result.detail, isNot(contains('section')));
    });

    test('a State-Version tag that is not a major.minor version', () async {
      // Malformed, not unknown: a version nothing can parse cannot be
      // compared, so nothing has been established about whether this build
      // could have read the artifact. `1` is the bare integer this tag used to
      // carry, and no artifact was ever published carrying it.
      await attachDrive(db);

      for (final tagged in [
        '1',
        '1.0.0',
        'x.y',
        '1.-1',
        '',
        '01.0',
        ' 1.0',
        '99999999999999999999.0',
        null,
      ]) {
        final artifact = await sealArtifact(
          await exportedPayload(),
          blockEnd: 900,
          stateVersion: tagged,
          // `null` is the absent tag, which is the same fact to a reader as
          // an unparseable one: there is no version to compare.
          omitStateVersionTag: tagged == null,
        );

        final result = await importer.import(
          candidate: artifact.candidate,
          body: artifact.body,
          protection: privateDrive,
          expectedOwnerAddress: ownerAddress,
        );

        expect(
          result.outcome,
          DriveStateOutcome.integrityFailed,
          reason: '"$tagged" is not a version to compare against',
        );
        expect(await fileRows(db), isEmpty);
      }
    });

    test('a State-Version tag settles it before a signature is verified',
        () async {
      // What reading the tag buys. It is the only version available before the
      // body is decrypted, so an artifact this build was never going to read
      // costs one GraphQL result rather than a download, a decryption and a
      // signature verification.
      //
      // Proven by handing it a body that is not an envelope at all: if the tag
      // were not consulted first, the codec would fail on those bytes and the
      // rejection would be about the envelope rather than about the version.
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      final notAnEnvelope = Uint8List.fromList(List.filled(64, 7));

      for (final tagged in ['2.0', '0.9']) {
        final tags = Map<String, String>.from(artifact.candidate.tags)
          ..[EntityTag.stateVersion] = tagged;

        final result = await importer.import(
          candidate: DriveStateArtifactCandidate(
            txId: artifact.candidate.txId,
            ownerAddress: ownerAddress,
            tags: tags,
          ),
          body: notAnEnvelope,
          protection: privateDrive,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.outcome, DriveStateOutcome.unknownVersion);
        expect(result.detail, contains('State-Version'));
        expect(result.detail, contains(tagged));
      }
    });

    // While the format version is in the 0.x range the additive-minor rule is
    // deliberately suspended — an unknown minor is a different format, not an
    // extension of this one. The above-1.0 behaviour it used to assert is
    // covered by `readableBy` in drive_state_format_version_test, which can
    // test both regimes because it names the reader instead of reading the
    // constant.
    test('a minor this build has never heard of is refused while at 0.x',
        () async {
      // While the major is 0 the minor is the compatibility unit, so 1.7 and
      // this build's version are two formats rather than one with an addition
      // in it. Tagged and signed at the same 1.7 because a producer writes one
      // constant into both.
      await attachDrive(db);
      final payload = editArtifact(
        await exportedPayload(),
        ["UPDATE meta SET version = '1.7'"],
      );

      final artifact = await sealArtifact(
        payload,
        blockEnd: 900,
        stateVersion: '1.7',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
      expect(result.detail, contains('1.7'));
      expect(await fileRows(db), isEmpty);
    });

    test('a table this reader does not know is refused, not ignored',
        () async {
      // The JSON payload ignored a section it did not know, so a producer
      // could add an optional one without stranding older clients. The SQLite
      // container reverses that on purpose: the schema gate matches
      // `sqlite_master` against the frozen schema byte for byte, because a
      // reader that tolerated an unknown table would be running its own
      // statements against a shape nobody agreed to. An addition therefore
      // costs a major version bump, which is the price of the gate.
      await attachDrive(db);
      final payload = editArtifact(
        await exportedPayload(),
        ['CREATE TABLE aggregate_totals (whatever INTEGER)'],
      );

      final artifact = await sealArtifact(payload, blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('aggregate_totals'));
      expect(await fileRows(db), isEmpty);
    });

    test('a State-Version tag that disagrees with the signed payload',
        () async {
      // The same shape as the `Block-Start`/`Block-End` cross-check, and
      // settled the same way: the tag is chosen by whoever posts the
      // transaction and nobody signs it, the payload field is the owner's.
      // A disagreement in the minor alone is still a disagreement - "the minor
      // changes nothing this reader dispatches on" is true and is not a reason
      // to believe the half anybody can rewrite.
      await attachDrive(db);

      // The tag is the one this build reads, so step 2 passes and the
      // disagreement is the only thing left to refuse the artifact.
      for (final declared in ['0.2', '0.9']) {
        final payload = editArtifact(
          await exportedPayload(),
          ["UPDATE meta SET version = '$declared'"],
        );

        final artifact = await sealArtifact(payload, blockEnd: 900);

        final result = await importer.import(
          candidate: artifact.candidate,
          body: artifact.body,
          protection: privateDrive,
          expectedOwnerAddress: ownerAddress,
        );

        expect(
          result.outcome,
          DriveStateOutcome.integrityFailed,
          reason: 'tagged $currentVersionString over a payload signed '
              '$declared',
        );
        expect(result.detail, contains(currentVersionString));
        expect(result.detail, contains(declared));
        expect(await fileRows(db), isEmpty);
      }
    });

    test('a cipher that is not AES256-GCM', () async {
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        cipher: 'AES256-CTR',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
    });

    test('a Cipher tag with no Cipher-IV beside it', () async {
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        omitCipherIvTag: true,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      // Not `privacyMismatch`: a half-written cipher tag pair is not a
      // statement about privacy, it is an artifact nobody can address.
      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('cipher tags'));
      expect(await fileRows(db), isEmpty);
    });

    test('a Cipher-IV tag with no Cipher beside it', () async {
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        omitCipherTag: true,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(await fileRows(db), isEmpty);
    });

    test('tags an indexer reported wrong, or not at all', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      final tags = Map<String, String>.from(artifact.candidate.tags)
        ..remove(EntityTag.blockEnd);

      final result = await importer.import(
        candidate: DriveStateArtifactCandidate(
          txId: artifact.candidate.txId,
          ownerAddress: ownerAddress,
          tags: tags,
        ),
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('Block-End'));
    });

    test('a Cipher-IV tag that is not base64', () async {
      await attachDrive(db);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      final tags = Map<String, String>.from(artifact.candidate.tags)
        ..[EntityTag.cipherIv] = 'not base64 at all !!';

      final result = await importer.import(
        candidate: DriveStateArtifactCandidate(
          txId: artifact.candidate.txId,
          ownerAddress: ownerAddress,
          tags: tags,
        ),
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, isNot(DriveStateOutcome.used));
    });

    test('a payload that is not a drive state container', () async {
      await attachDrive(db);
      // Bytes that are not a database at all, so there is no schema to gate
      // and the refusal comes from the attach itself.
      final artifact = await sealArtifact(
        Uint8List.fromList(List.filled(64, 7)),
        blockEnd: 900,
        entityCount: 0,
        payloadIsOpaque: true,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
    });

    test('a signed payload whose version is not this build\'s is refused, '
        'in both directions', () async {
      // The tag is the one this build reads and passes; the version inside
      // the signature is what refuses the artifact. That is the copy that
      // governs, because it is the only one the owner signed.
      //
      // Reported as `integrityFailed` rather than `unknownVersion`, and the
      // difference is worth naming. The JSON reader gated the payload's own
      // version as it parsed it, so a signed 9.0 came back as "your client is
      // old". `readArtifactAsExport` has no such gate - it parses
      // `meta.version` and hands it on - so what refuses these is the
      // tag/payload cross-check one step later. Nothing unreadable is
      // accepted either way; what is lost is the sentence a sync log gets.
      await attachDrive(db);

      for (final declared in ['9.0', '0.0']) {
        final payload = editArtifact(
          await exportedPayload(),
          ["UPDATE meta SET version = '$declared'"],
        );

        final artifact = await sealArtifact(payload, blockEnd: 900);
        final result = await importer.import(
          candidate: artifact.candidate,
          body: artifact.body,
          protection: privateDrive,
          expectedOwnerAddress: ownerAddress,
        );

        expect(
          result.outcome,
          DriveStateOutcome.integrityFailed,
          reason: 'a payload signed $declared',
        );
        expect(result.detail, contains(declared));
        expect(await fileRows(db), isEmpty);
      }
    });

    test('a signed payload whose version cannot be parsed', () async {
      await attachDrive(db);

      // `meta.version` is `TEXT NOT NULL`, so the absent and non-string cases
      // the JSON payload could hold have no expression here: a missing value
      // is a row the insert refuses to write, and an integer 1 is stored as
      // the string '1' by the column's affinity. What is left is every
      // string that is not a `major.minor` version.
      for (final declared in ['1', '1.0.0', 'x.y', '']) {
        final payload = editArtifact(
          await exportedPayload(),
          ["UPDATE meta SET version = '$declared'"],
        );

        final artifact = await sealArtifact(payload, blockEnd: 900);
        final result = await importer.import(
          candidate: artifact.candidate,
          body: artifact.body,
          protection: privateDrive,
          expectedOwnerAddress: ownerAddress,
        );

        expect(
          result.outcome,
          DriveStateOutcome.integrityFailed,
          reason: '"$declared" is not a version to compare against',
        );
        expect(await fileRows(db), isEmpty);
      }
    });

    test('a drive this client does not have', () async {
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains(driveId));
      // Emphatically not rows hanging off a drive that is not there.
      expect(await fileRows(db), isEmpty);
      expect(await folderRows(db), isEmpty);
    });

    test('a database that goes away mid-import', () async {
      final gone = getTestDb();
      await attachDrive(gone);
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);
      await gone.close();

      final result =
          await DriveStateImporter(gone.driveDao, codec: codec).import(
        candidate: artifact.candidate,
        body: artifact.body,
        protection: privateDrive,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.isImported, isFalse);
      expect(result.outcome.kind, DriveStateOutcomeKind.rejected);
    });

    test('a signature this build cannot check is an authorship failure', () {
      // Not `unknownVersion`. Nothing about the artifact's authorship was
      // established - the check could not be run at all - and reporting that
      // as "your client is old" would file an unverifiable artifact under the
      // same code as a legitimately newer one, which is the distinction §7
      // exists to keep.
      expect(
        DriveStateEnvelopeFailure.unsupportedSignatureType.outcome,
        DriveStateOutcome.signatureFailed,
      );
      // The cipher case above it is the genuine forward-compatibility one and
      // stays where it is.
      expect(
        DriveStateEnvelopeFailure.unsupportedCipher.outcome,
        DriveStateOutcome.unknownVersion,
      );
    });

    test('a decompression bomb is a rejection, not a crash', () {
      expect(
        DriveStateEnvelopeFailure.decompressedTooLarge.outcome,
        DriveStateOutcome.integrityFailed,
      );
    });

    test('every envelope failure has a reason a reader can act on', () {
      // The envelope lane enumerates eleven ways an artifact can be
      // unreadable; §7's vocabulary is coarser on purpose. What must hold is
      // that none of them falls through to "used" or "none found", which are
      // the two answers that would make a rejected artifact invisible.
      for (final failure in DriveStateEnvelopeFailure.values) {
        expect(
          failure.outcome.kind,
          DriveStateOutcomeKind.rejected,
          reason: '${failure.name} must report as a rejection',
        );
      }
    });
  });
}
