import 'dart:convert';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';

import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../../test_utils/utils.dart';

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
  });

  /// The artifact as it reaches the importer: the transaction's data, and the
  /// tags an indexer reported for it.
  ///
  /// Every tag is a parameter because half of these tests are about a tag
  /// disagreeing with the body it describes.
  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      sealArtifact(
    Map<String, dynamic> payload, {
    String taggedDriveId = driveId,
    required int blockEnd,
    int blockStart = 0,
    int? entityCount,
    String stateVersion = '1',
    String? cipher,
    SecretKey? key,
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
  }) async {
    if (omitSignedCoverage) {
      payload.remove('coverage');
    } else {
      payload['coverage'] =
          signedCoverage ?? {'blockStart': blockStart, 'blockEnd': blockEnd};
    }

    final sealed = await codec.seal(
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      driveKey: key ?? driveKey,
      wallet: signer ?? owner,
    );
    expect(sealed.isSealed, isTrue, reason: sealed.toString());
    final envelope = sealed.envelope!;

    final sections = payload['sections'] as Map<String, dynamic>;
    int rowsIn(String section) =>
        ((sections[section] as Map<String, dynamic>?)?['rows'] as List?)
            ?.length ??
        0;

    return (
      candidate: DriveStateArtifactCandidate(
        txId: 'artifact-tx-id',
        ownerAddress: ownerAddress,
        tags: {
          EntityTag.arFs: '0.15',
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: taggedDriveId,
          EntityTag.driveStateId: 'drive-state-id',
          EntityTag.stateVersion: stateVersion,
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '$blockStart',
          EntityTag.blockEnd: '$blockEnd',
          EntityTag.entityCount:
              '${entityCount ?? rowsIn(driveSectionName) + rowsIn(folderEntriesSectionName) + rowsIn(fileEntriesSectionName)}',
          EntityTag.cipher: cipher ?? Cipher.aes256,
          EntityTag.cipherIv: envelope.cipherIvAsBase64,
        },
        minedAtHeight: blockEnd,
      ),
      body: envelope.body,
    );
  }

  /// The producer's export, as the plain JSON a payload actually arrives as,
  /// so a test can reach in and make one field disagree with its tags.
  Future<Map<String, dynamic>> exportedPayload([String id = driveId]) async {
    final export = await exportDriveState(producerDb.driveDao, id);
    return jsonDecode(jsonEncode(export.toJson())) as Map<String, dynamic>;
  }

  List<Map<String, dynamic>> rowsOf(
    Map<String, dynamic> payload,
    String section,
  ) =>
      ((payload['sections'] as Map<String, dynamic>)[section]
              as Map<String, dynamic>)['rows']
          .cast<Map<String, dynamic>>();

  /// Attaches a drive to the consumer, the way a client that is about to sync
  /// one already has it: a row, its key material, and nothing synced yet.
  Future<void> attachDrive(
    Database into, {
    String id = driveId,
    String rootFolder = rootFolderId,
    String name = 'stale-local-name',
    int? lastBlockHeight,
    DateTime? lastUpdated,
  }) =>
      into.into(into.drives).insert(
            DrivesCompanion.insert(
              id: id,
              rootFolderId: rootFolder,
              ownerAddress: ownerAddress,
              name: name,
              privacy: DrivePrivacyTag.private,
              encryptedKey: Value(Uint8List.fromList([1, 2, 3, 4])),
              keyEncryptionIv: Value(Uint8List.fromList([5, 6, 7])),
              driveKeyGenerated: const Value(true),
              syncCursor: const Value('a-local-gateway-cursor'),
              lastBlockHeight: Value(lastBlockHeight ?? 0),
              lastUpdated: Value(lastUpdated ?? DateTime(2020)),
            ),
          );

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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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

  group('merging, not replacing', () {
    test('does not clobber a row the database holds a newer copy of', () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      final artifactFile = rowsOf(payload, fileEntriesSectionName).first;
      final contestedId = artifactFile['id'] as String;
      final afterTheArtifact = DateTime.fromMillisecondsSinceEpoch(
              artifactFile['lastUpdated'] as int)
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.countMismatch);
      expect(result.detail, contains('99'));
      await expectNothingWritten();
    });

    test('rejects a payload for a different drive than the Drive-Id tag',
        () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      rowsOf(payload, driveSectionName).first['id'] =
          'a-completely-other-drive';

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains('a-completely-other-drive'));
      await expectNothingWritten();
    });

    test('rejects a payload carrying a row that belongs to another drive',
        () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      rowsOf(payload, fileEntriesSectionName).first['driveId'] = otherDriveId;

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
      expect(result.detail, contains(otherDriveId));
      await expectNothingWritten();
    });

    test('rejects a payload whose owner is not the one it verified against',
        () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      rowsOf(payload, driveSectionName).first['ownerAddress'] = 'someone-else';

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: driveKey,
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
        driveKey: await aesGcm.newSecretKey(),
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
        driveKey: driveKey,
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
        driveKey: driveKey,
        expectedOwnerAddress: 'not-the-owner',
      );

      expect(result.outcome, DriveStateOutcome.signatureFailed);
      expect(await fileRows(db), isEmpty);
    });

    test('a State-Version this build does not read', () async {
      await attachDrive(db);
      final artifact = await sealArtifact(
        await exportedPayload(),
        blockEnd: 900,
        stateVersion: '2',
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
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
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
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
        driveKey: driveKey,
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
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, isNot(DriveStateOutcome.used));
    });

    test('a payload that is not a drive state container', () async {
      await attachDrive(db);
      final artifact = await sealArtifact(
        {'version': 1, 'sections': <String, dynamic>{}},
        blockEnd: 900,
        entityCount: 0,
      );

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.integrityFailed);
    });

    test('a payload from a format version newer than this build', () async {
      await attachDrive(db);
      final payload = await exportedPayload();
      payload['version'] = driveStateFormatVersion + 1;

      final artifact = await sealArtifact(payload, blockEnd: 900);
      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(result.outcome, DriveStateOutcome.unknownVersion);
    });

    test('a drive this client does not have', () async {
      final artifact =
          await sealArtifact(await exportedPayload(), blockEnd: 900);

      final result = await importer.import(
        candidate: artifact.candidate,
        body: artifact.body,
        driveKey: driveKey,
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
        driveKey: driveKey,
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
