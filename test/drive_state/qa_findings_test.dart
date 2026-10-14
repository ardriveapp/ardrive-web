import 'dart:io';

import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart'
    as sqlite;
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../drive_state_sqlite/artifact_fixture.dart' as fixture;
import '../test_utils/utils.dart';

/// The one version this build writes and reads. Tests follow the constant
/// rather than restating it, so moving the format version does not mean
/// editing every fixture — which is how a fixture ends up asserting a
/// version the code no longer speaks.
String get currentVersionString => DriveStateFormatVersion.current.toString();

/// Independent QA findings against the drive state artifact.
///
/// Every test here **failed** when it was written, against the branch as it
/// then stood. Each one is a defect, not a preference, and each is written the
/// way a user meets it rather than the way the code is shaped. They all pass
/// now; they are kept because the defects they describe are the ones this
/// format is most likely to reacquire — a file whose parent never travelled, a
/// stand-in row outranking the real one, a drive row pointing at a folder
/// nobody carries.
void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';

  /// A folder whose own metadata was never found on chain, so sync invented a
  /// stand-in for it: `isGhost: true`, named after its own uuid, parented to
  /// the drive root, stamped `DateTime.now()`. `SyncRepository.createGhosts`.
  /// A normal state, per `lib/sync/domain/ghost_folder.dart` — not corruption.
  const ghostFolderId = 'ghost-folder-id';

  /// The file that *caused* the ghost: it names a parent whose metadata sync
  /// never read. It has a revision, so it is chain-derived and travels.
  const orphanedFileId = 'file-under-a-ghost';

  final createdAt = DateTime(2024, 1, 1);

  final codec = DriveStateEnvelopeCodec();
  final aesGcm = AesGcm.with256bits();

  late Wallet owner;
  late String ownerAddress;
  late SecretKey driveKey;
  late DriveStateProtection privateDrive;

  late Database producerDb;
  late Database consumerDb;
  late DriveStateImporter importer;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    owner = await Wallet.generate();
    ownerAddress = await owner.getAddress();
    driveKey = await aesGcm.newSecretKey();
    privateDrive = DriveStateProtection.forDrive(
      privacy: DrivePrivacyTag.private,
      driveKey: driveKey,
    ).protection!;
  });

  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      publishArtifact() async {
    // A SQLite database, built the way the producer builds one, so every
    // finding below is met through the real container.
    final artifact = await sqlite.exportDriveState(
      producerDb,
      driveId: driveId,
      sink: await createArtifactSink('qa-findings'),
      blockEnd: await _watermark(producerDb, driveId),
    );
    final sealed = await codec.seal(
      plaintext: artifact.bytes,
      protection: privateDrive,
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
          EntityTag.driveId: driveId,
          EntityTag.driveStateId: 'drive-state-id',
          EntityTag.stateVersion: currentVersionString,
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '0',
          EntityTag.blockEnd: '${artifact.blockEnd}',
          EntityTag.entityCount: '${artifact.entityCount}',
          EntityTag.cipher: Cipher.aes256,
          EntityTag.cipherIv: envelope.cipherIvAsBase64!,
        },
        minedAtHeight: artifact.blockEnd,
      ),
      body: envelope.body,
    );
  }

  Future<DriveStateImportResult> publishAndImport() async {
    final artifact = await publishArtifact();
    return importer.import(
      candidate: artifact.candidate,
      body: artifact.body,
      protection: privateDrive,
      expectedOwnerAddress: ownerAddress,
    );
  }

  /// The producer's drive: a root folder that synced properly, a ghost folder
  /// that did not, and a file inside the ghost.
  Future<void> seedProducerWithAGhost() async {
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
          lastUpdated: Value(createdAt),
        ),
      );

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

      batch.insertAll(producerDb.folderEntries, [
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'a published drive',
          path: '',
          lastUpdated: Value(createdAt),
        ),
        // Exactly what `SyncRepository.createGhosts` writes.
        FolderEntriesCompanion.insert(
          id: ghostFolderId,
          driveId: driveId,
          parentFolderId: const Value(rootFolderId),
          name: ghostFolderId,
          path: '',
          isGhost: const Value(true),
          dateCreated: Value(DateTime.now()),
          lastUpdated: Value(DateTime.now()),
        ),
      ]);

      // Only the root folder has a revision. A ghost has none by definition —
      // that is what makes it a ghost.
      batch.insert(
        producerDb.folderRevisions,
        FolderRevisionsCompanion.insert(
          folderId: rootFolderId,
          driveId: driveId,
          name: 'a published drive',
          metadataTxId: 'root-folder-metadata-tx',
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
        ),
      );

      batch.insert(
        producerDb.fileEntries,
        FileEntriesCompanion.insert(
          id: orphanedFileId,
          driveId: driveId,
          parentFolderId: ghostFolderId,
          name: 'the-users-tax-return.pdf',
          dataTxId: 'orphan-data-tx',
          size: 4096,
          path: '',
          dataContentType: const Value('application/pdf'),
          lastModifiedDate: createdAt,
          dateCreated: Value(createdAt),
          lastUpdated: Value(createdAt),
        ),
      );

      batch.insert(
        producerDb.fileRevisions,
        FileRevisionsCompanion.insert(
          fileId: orphanedFileId,
          driveId: driveId,
          parentFolderId: ghostFolderId,
          name: 'the-users-tax-return.pdf',
          size: 4096,
          lastModifiedDate: createdAt,
          metadataTxId: 'orphan-metadata-tx',
          dataTxId: 'orphan-data-tx',
          action: RevisionAction.create,
          dateCreated: Value(createdAt),
          dataContentType: const Value('application/pdf'),
        ),
      );

      batch.insertAll(producerDb.networkTransactions, [
        for (final txId in [
          'drive-metadata-tx',
          'root-folder-metadata-tx',
          'orphan-metadata-tx',
          'orphan-data-tx',
        ])
          NetworkTransactionsCompanion.insert(
            id: txId,
            status: const Value(TransactionStatus.confirmed),
            dateCreated: Value(createdAt),
          ),
      ]);
    });
  }

  Future<void> attachDriveToConsumer() =>
      consumerDb.into(consumerDb.drives).insert(
            DrivesCompanion.insert(
              id: driveId,
              rootFolderId: rootFolderId,
              ownerAddress: ownerAddress,
              name: 'a published drive',
              privacy: DrivePrivacyTag.private,
              encryptedKey: Value(Uint8List.fromList([1, 2, 3, 4])),
              keyEncryptionIv: Value(Uint8List.fromList([5, 6, 7])),
              driveKeyGenerated: const Value(true),
              lastBlockHeight: const Value(0),
              lastUpdated: Value(DateTime(2020)),
            ),
          );

  setUp(() async {
    producerDb = getTestDb();
    consumerDb = getTestDb();
    importer = DriveStateImporter(consumerDb.driveDao, codec: codec);
  });

  tearDown(() async {
    await consumerDb.close();
    await producerDb.close();
  });

  /// FINDING 1 — a file whose parent folder is not in the payload is imported
  /// with a `parentFolderId` naming a folder that is not there. Nothing in the
  /// app lists a file by anything but its parent, so the file is invisible;
  /// and the import advances the watermark past the range whose metadata would
  /// have made sync re-derive the ghost, so it stays invisible.
  ///
  /// The two containers reach the same requirement by different roads. The
  /// JSON export filtered `folder_entries` down to the rows a revision
  /// vouched for, so a ghost never travelled and the importer had to rebuild
  /// one. The SQLite export copies the table whole, so the producer's ghost
  /// row travels as it stands — which is why the assertion below is on the
  /// folder existing, not on which side put it there.
  group('a drive with a ghost folder', () {
    setUp(() async {
      await seedProducerWithAGhost();
      await attachDriveToConsumer();
    });

    test('the producer can see the file inside its own ghost folder', () async {
      // The control. The ghost renders in the producer's own client.
      final root = await producerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first;
      expect(root.subfolders.map((f) => f.id), [ghostFolderId]);

      final ghost = await producerDb.driveDao
          .watchFolderContents(driveId, folderId: ghostFolderId)
          .first;
      expect(ghost.files.map((f) => f.id), [orphanedFileId]);
    });

    test('the consumer imports the file and can never reach it', () async {
      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      // The row landed.
      final files = await consumerDb.select(consumerDb.fileEntries).get();
      expect(files.map((f) => f.id), [orphanedFileId]);

      // The folder it hangs off did not.
      final folders = await consumerDb.select(consumerDb.folderEntries).get();
      expect(
        folders.map((f) => f.id),
        contains(ghostFolderId),
        reason: 'the artifact must carry, or the importer must rebuild, a '
            'folder for every parentFolderId its files name — otherwise the '
            'file is in the database and in no folder',
      );

      // And this is what the user sees: an empty drive holding one file.
      final root = await consumerDb.driveDao
          .watchFolderContents(driveId, folderId: rootFolderId)
          .first;
      expect(
        root.subfolders.map((f) => f.id),
        [ghostFolderId],
        reason: 'the file is unreachable from the drive root',
      );
    });
  });

  /// FINDING 2 — the merge's "newest lastUpdated wins" rule is decided against
  /// a timestamp the *consumer* fabricated. A ghost row is stamped
  /// `DateTime.now()`; the artifact's genuine row carries its chain commit
  /// time, which is by definition older. So the artifact's real folder loses
  /// to the consumer's stand-in, and the drive keeps a uuid-named folder
  /// parented to its root instead of the real one.
  ///
  /// The JSON export lane guarded the mirror image of this — it refused to
  /// *publish* a fabricated row, for exactly this reason
  /// (`_folderEntryCameFromChain`). The SQLite export copies `folder_entries`
  /// whole and has no such filter, so what stands between a producer's
  /// stand-in and a consumer's real row is the import side alone:
  /// `_folderStandInLoses`, which compares which folders each side has a
  /// revision for rather than which timestamp is newer.
  group('a consumer that already invented a stand-in row', () {
    const realFolderId = 'a-real-folder';

    setUp(() async {
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
            lastUpdated: Value(createdAt),
          ),
        );
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
        batch.insertAll(producerDb.folderEntries, [
          FolderEntriesCompanion.insert(
            id: rootFolderId,
            driveId: driveId,
            name: 'a published drive',
            path: '',
            lastUpdated: Value(createdAt),
          ),
          FolderEntriesCompanion.insert(
            id: realFolderId,
            driveId: driveId,
            parentFolderId: const Value(rootFolderId),
            name: 'Tax returns',
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
            folderId: realFolderId,
            driveId: driveId,
            parentFolderId: const Value(rootFolderId),
            name: 'Tax returns',
            metadataTxId: 'real-folder-metadata-tx',
            action: RevisionAction.create,
            dateCreated: Value(createdAt),
          ),
        ]);
        batch.insertAll(producerDb.networkTransactions, [
          for (final txId in [
            'drive-metadata-tx',
            'root-folder-metadata-tx',
            'real-folder-metadata-tx',
          ])
            NetworkTransactionsCompanion.insert(
              id: txId,
              status: const Value(TransactionStatus.confirmed),
              dateCreated: Value(createdAt),
            ),
        ]);
      });

      await attachDriveToConsumer();

      // The consumer's own earlier sync could not read this folder's metadata
      // and invented a ghost for it, stamped now.
      await consumerDb.into(consumerDb.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: realFolderId,
              driveId: driveId,
              parentFolderId: const Value(rootFolderId),
              name: realFolderId,
              path: '',
              isGhost: const Value(true),
              dateCreated: Value(DateTime.now()),
              lastUpdated: Value(DateTime.now()),
            ),
          );
    });

    test('the artifact heals the ghost it carries the real row for', () async {
      final result = await publishAndImport();
      expect(result.outcome, DriveStateOutcome.used, reason: result.detail);

      final folder = await (consumerDb.select(consumerDb.folderEntries)
            ..where((f) => f.id.equals(realFolderId)))
          .getSingle();

      expect(
        folder.isGhost,
        isFalse,
        reason: 'the artifact carries the real folder; a stand-in row the '
            'consumer stamped with DateTime.now() must not outrank it',
      );
      expect(folder.name, 'Tax returns');
    });
  });

  /// FINDING 3 — nothing checks that `drives.rootFolderId` names a folder the
  /// payload carries, and the importer adopts it wholesale.
  ///
  /// `DriveDao` already documents what a missing root folder row costs:
  ///
  /// > the drive cannot be opened at all: `watchFolderContents` drops the
  /// > missing folder with a `.where` and its combined stream then never
  /// > emits, stranding the explorer on a spinner that nothing retries.
  ///
  /// That is the bug `_rootFolderPlaceholder` was added to fix. An artifact
  /// can put a drive straight back into it, and worse than sync could: the
  /// artifact is immutable, its coverage equals the watermark it just wrote,
  /// and equal coverage is re-imported — so it re-applies on every sync.
  group('an artifact whose drive row points at a folder it does not carry', () {
    setUp(() async {
      await seedProducerWithAGhost();
      // The producer's drive row names a root folder that no section carries.
      // Reachable from a broken producer — a drive whose root folder metadata
      // never resolved has a placeholder row, which the export's
      // chain-derived filter drops — and trivially reachable from a hostile
      // one, since an artifact is authentic, signed and permanent.
      await producerDb.driveDao.writeToDrive(
        const DrivesCompanion(
          id: Value(driveId),
          rootFolderId: Value('a-folder-that-is-in-no-section'),
        ),
      );
      await attachDriveToConsumer();
    });

    test('is refused, or its root folder is materialised', () async {
      final result = await publishAndImport();

      if (result.isImported) {
        final drive = await (consumerDb.select(consumerDb.drives)
              ..where((d) => d.id.equals(driveId)))
            .getSingle();
        final root = await (consumerDb.select(consumerDb.folderEntries)
              ..where((f) =>
                  f.driveId.equals(driveId) & f.id.equals(drive.rootFolderId)))
            .getSingleOrNull();

        expect(
          root,
          isNot(null),
          reason: 'the drive now names a root folder with no row behind it. '
              'watchFolderContents never emits for such a drive, and '
              'getFolderTree throws — the explorer spins forever, on every '
              'sync, permanently',
        );
      }
    });
  });

  /// FINDING 3 — the arithmetic behind D5.
  ///
  /// `DriveStateEnvelopeCodec.seal` refuses above
  /// `DriveStateEnvelopeCodec.defaultMaxPlaintextBytes` (100 MiB), and since
  /// D12 what it weighs is the SQLite file. An earlier version of this test
  /// weighed JSON rows, which described the D1 container and put the
  /// crossover at about half its real figure.
  ///
  /// This builds real artifacts from rows as wide as a real drive's at two
  /// sizes, so the fixed cost of the schema drops out of the per-file figure
  /// and the extrapolation is a straight line, measured on every run.
  group('payload size against the seal boundary', () {
    Future<int> artifactBytes(int files) async {
      final db = getTestDb();
      try {
        await fixture.seedRealisticDrive(db, files: files);
        final artifact = await sqlite.exportDriveState(
          db,
          driveId: fixture.testDriveId,
          sink: await createArtifactSink('d5-$files'),
          blockEnd: 1814228,
        );
        return artifact.bytes.length;
      } finally {
        await db.close();
      }
    }

    test('a 42k-file drive fits under the 100 MiB seal boundary', () async {
      const target = 41767;
      const payloadLimit = DriveStateEnvelopeCodec.defaultMaxPlaintextBytes;

      final small = await artifactBytes(1000);
      final large = await artifactBytes(3000);
      final perFile = (large - small) / 2000;
      final fixed = small - perFile * 1000;
      final atTarget = fixed + perFile * target;
      final crossover = ((payloadLimit - fixed) / perFile).floor();
      final headroom = payloadLimit / atTarget;

      // ignore: avoid_print
      print('${perFile.toStringAsFixed(1)} B per file on '
          '${fixed.round()} B fixed; $target files weigh '
          '${(atTarget / 1048576).toStringAsFixed(1)} MiB; the '
          '${payloadLimit ~/ 1048576} MiB boundary is crossed at about '
          '$crossover files, ${headroom.toStringAsFixed(2)}x headroom');

      expect(atTarget, lessThan(payloadLimit));

      // Bands rather than equalities: the point is that the figure the doc
      // quotes tracks the exported row shape. Widen the rows and this fails,
      // which is when the doc needs an edit, not a year later when a user
      // meets the refusal.
      expect(
        crossover,
        inInclusiveRange(152000, 176000),
        reason: 'docs/DRIVE_STATE_ARTIFACT.md §2.3 quotes about 164,000 '
            'files; the exported row shape has moved under it',
      );
      expect(
        headroom,
        inInclusiveRange(3.7, 4.2),
        reason: 'docs/DRIVE_STATE_ARTIFACT.md §2.3 quotes roughly 3.9x '
            'headroom over the 42k-file drive',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the proposal states the measured boundary, not the extrapolated one',
        () {
      // The numbers above are only worth measuring if the document a reader
      // plans against carries them. §2.3 is where D5's refusal is sized.
      final proposal = File('docs/DRIVE_STATE_ARTIFACT.md').readAsStringSync();

      expect(
        proposal,
        isNot(contains('somewhere near 120k entities')),
        reason: 'the ~120k extrapolation is wrong by ~1.6x and sizes a '
            'refusal users will actually meet',
      );
      // The measured SQLite figure is the one a reader plans against, and
      // the JSON-era range stays quoted as history so nobody re-derives it.
      expect(proposal, contains('about 164,000 files'));
      expect(proposal, contains('roughly 3.9x'));
      expect(proposal, contains('between 70,000 and 80,000 files'));

      // And it no longer justifies the bound by the cipher, which is the
      // reasoning D11 removed: a public drive's artifact has no cipher and
      // pays the same producer-memory cost.
      expect(proposal, contains("the size bound is not the cipher's"));
      expect(proposal, contains('producer\'s memory'));
    });
  });
}

/// The producer's own sync watermark, which is what an artifact may claim and
/// nothing more.
Future<int> _watermark(Database db, String driveId) async {
  final row = await db
      .customSelect(
        'SELECT lastBlockHeight FROM drives WHERE id = ?',
        variables: [Variable<String>(driveId)],
      )
      .getSingle();
  return row.readNullable<int>('lastBlockHeight') ?? 0;
}
