import 'dart:convert';

import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_service.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:drift/drift.dart';
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

  final codec = DriveStateEnvelopeCodec();
  final aesGcm = AesGcm.with256bits();

  late Wallet owner;
  late String ownerAddress;
  late SecretKey driveKey;

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

  /// Export, seal, and hand back exactly what a consumer receives: the
  /// transaction body and the tags an indexer reported for it.
  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      publishArtifact() async {
    final export = await exportDriveState(producerDb.driveDao, driveId);
    final payload = jsonEncode(export.toJson());

    final sealed = await codec.seal(
      plaintext: Uint8List.fromList(utf8.encode(payload)),
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
          EntityTag.stateVersion: '1',
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
}
