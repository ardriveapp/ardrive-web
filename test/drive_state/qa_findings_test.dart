import 'dart:convert';
import 'dart:io';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:drift/drift.dart';
import 'package:test/test.dart';

import '../test_utils/utils.dart';

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

  late Database producerDb;
  late Database consumerDb;
  late DriveStateImporter importer;

  setUpAll(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    owner = await Wallet.generate();
    ownerAddress = await owner.getAddress();
    driveKey = await aesGcm.newSecretKey();
  });

  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      publishArtifact() async {
    final export = await exportDriveState(producerDb.driveDao, driveId);
    final sealed = await codec.seal(
      plaintext: Uint8List.fromList(utf8.encode(jsonEncode(export.toJson()))),
      driveKey: driveKey,
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
          EntityTag.driveId: driveId,
          EntityTag.driveStateId: 'drive-state-id',
          EntityTag.stateVersion: '1.0',
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '${export.coverage.blockStart}',
          EntityTag.blockEnd: '${export.coverage.blockEnd}',
          EntityTag.entityCount: '${export.entityCount}',
          EntityTag.cipher: Cipher.aes256,
          EntityTag.cipherIv: envelope.cipherIvAsBase64,
        },
        minedAtHeight: export.coverage.blockEnd,
      ),
      body: envelope.body,
    );
  }

  Future<DriveStateImportResult> publishAndImport() async {
    final artifact = await publishArtifact();
    return importer.import(
      candidate: artifact.candidate,
      body: artifact.body,
      driveKey: driveKey,
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

  /// FINDING 1 — a ghost folder is dropped from the payload, and every file
  /// inside it is imported with a `parentFolderId` naming a folder that is not
  /// there. Nothing in the app lists a file by anything but its parent, so the
  /// file is invisible; and the import advances the watermark past the range
  /// whose metadata would have made sync re-derive the ghost, so it stays
  /// invisible.
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
  /// The export lane guards the mirror image of this — it refuses to *publish*
  /// a fabricated row, for exactly this reason (`_folderEntryCameFromChain`).
  /// The import side has no such guard.
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
  /// `DriveStateEnvelopeCodec.seal` refuses at
  /// `maxSizeSupportedByGCMEncryption` (100 MiB), measured against the
  /// **uncompressed JSON**. The proposal's 34.63 MiB figure is a VACUUMed
  /// SQLite file, not JSON, and it was computed before `file_revisions`,
  /// `folder_revisions`, `drive_revisions` and `licenses` were added to the
  /// payload (decision D2, reversed).
  ///
  /// This measures the real thing at the stated target: 41,767 entities,
  /// 1.05 revisions each.
  group('payload size against the AES-GCM boundary', () {
    /// A row's worth of realistic values: uuids are 36 characters, Arweave
    /// transaction ids are 43, and a name and a path are what a real drive
    /// carries.
    const uuid = '0a36156c-6274-41a2-87b0-372f4da7f568';
    const txId = 'DzvFP9VWdSbznuhbtRNT2g0QKnwxvBcQKcYqCtBd7yQ';

    test('a 42k-file drive fits under the 100 MiB seal boundary', () {
      const fileCount = 41767;
      const revisionsPerFile = 1.05;

      final file = ExportedFileEntry(
        id: uuid,
        driveId: uuid,
        name: 'IMG_20211213_120145.jpg',
        parentFolderId: uuid,
        path: '/Photos/2021/12/IMG_20211213_120145.jpg',
        size: 3457812,
        lastModifiedDate: DateTime(2021, 12, 13),
        dataContentType: 'image/jpeg',
        dataTxId: txId,
        licenseTxId: null,
        bundledIn: txId,
        thumbnail: null,
        pinnedDataOwnerAddress: null,
        customJsonMetadata: null,
        customGQLTags: null,
        isHidden: false,
        dateCreated: DateTime(2021, 12, 13),
        lastUpdated: DateTime(2021, 12, 13),
        assignedNames: null,
        fallbackTxId: null,
        originalOwner: null,
        importSource: null,
      );

      final revision = ExportedFileRevision(
        fileId: uuid,
        driveId: uuid,
        name: 'IMG_20211213_120145.jpg',
        parentFolderId: uuid,
        size: 3457812,
        lastModifiedDate: DateTime(2021, 12, 13),
        dataContentType: 'image/jpeg',
        metadataTxId: txId,
        dataTxId: txId,
        licenseTxId: null,
        thumbnail: null,
        bundledIn: txId,
        dateCreated: DateTime(2021, 12, 13),
        customJsonMetadata: null,
        customGQLTags: null,
        action: 'create',
        pinnedDataOwnerAddress: null,
        isHidden: false,
        assignedNames: null,
        fallbackTxId: null,
        originalOwner: null,
        importSource: null,
      );

      // `+ 1` for the comma that separates each row in the JSON array.
      final perFileEntry = jsonEncode(file.toJson()).length + 1;
      final perFileRevision = jsonEncode(revision.toJson()).length + 1;

      final estimate = (fileCount * perFileEntry) +
          (fileCount * revisionsPerFile).round() * perFileRevision;

      // ignore: avoid_print
      print('file_entries row: $perFileEntry bytes\n'
          'file_revisions row: $perFileRevision bytes\n'
          'estimated payload for $fileCount files at $revisionsPerFile '
          'revisions each: $estimate bytes '
          '(${(estimate / (1024 * 1024)).toStringAsFixed(1)} MiB) against a '
          '$maxSizeSupportedByGCMEncryption byte '
          '(${maxSizeSupportedByGCMEncryption ~/ (1024 * 1024)} MiB) limit');

      // The target drive fits, but not with the headroom the proposal implied.
      expect(estimate, lessThan(maxSizeSupportedByGCMEncryption));

      // An earlier draft of §2.3 read: "At 34.63 MiB for ~41k entities, that
      // boundary is somewhere near 120k entities and will be reached." That
      // figure is a VACUUMed SQLite file, not the JSON `seal` weighs, and it
      // counted entities rather than the entity *and* revision rows the
      // payload carries (D2). Measured against the wire format, the crossover
      // is here — and §2.3 now says so.
      final crossover = maxSizeSupportedByGCMEncryption ~/
          (perFileEntry + (perFileRevision * revisionsPerFile).round());
      final headroom = maxSizeSupportedByGCMEncryption / estimate;

      // ignore: avoid_print
      print('the AES-GCM boundary is crossed at about $crossover files, '
          'leaving ${headroom.toStringAsFixed(2)}x headroom over the target '
          'drive');

      expect(
        crossover,
        lessThan(120000),
        reason: 'the ~120k figure would only hold if `seal` weighed a VACUUMed '
            'SQLite file without revisions; it weighs JSON with them',
      );

      // A band rather than an equality: these are row sizes, and the point of
      // the test is that the documented figure tracks the exported row shape.
      // Widen the row types and this fails, which is when the doc needs an
      // edit — not a year later when a user meets the refusal.
      expect(
        crossover,
        inInclusiveRange(68000, 78000),
        reason: 'docs/DRIVE_STATE_ARTIFACT.md §2.3 quotes this fixture at '
            'about 73,000 files; the exported row shape has moved under it',
      );
      expect(
        headroom,
        inInclusiveRange(1.6, 1.9),
        reason: 'docs/DRIVE_STATE_ARTIFACT.md §2.3 quotes this fixture at '
            '~1.75x headroom over the 42k-file target drive',
      );
    });

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
      // Both measurements are quoted, and the range they bracket is what a
      // reader plans against. Asserting the range rather than either figure
      // keeps this from breaking every time one fixture's names change.
      expect(proposal, contains('~73,000 files'));
      expect(proposal, contains('~80,000 files'));
      expect(proposal, contains('between 70,000 and 80,000 files'));
    });
  });
}
