import 'package:ardrive/drive_state/domain/drive_state_format_version.dart';
import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart' show DriveKey;
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/data/drive_state_sync_source.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart'
    as sqlite;
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/constants.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart' show ArDriveThemes;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

/// The one version this build writes and reads. Fixtures follow the constant
/// rather than restating it — restating it is how a fixture ends up asserting
/// a version the code no longer speaks.
String get currentVersionString => DriveStateFormatVersion.current.toString();

/// Sync reading a drive state artifact as its first source
/// (`docs/DRIVE_STATE_ARTIFACT.md` §5).
///
/// Everything below the seam is real: a real database on both sides, a real
/// export, a real seal, and the real importer. Only the two things a test
/// cannot have are stood in for - the gateway, and the indexer that answers a
/// discovery query - because those are exactly the two the tests need to lie.
///
/// The assertion that matters most is not that rows land. It is the block
/// height the GraphQL pass starts from: an artifact that imports but does not
/// obscure its range costs a download and saves nothing, and the drive would
/// still walk every block over GraphQL with nothing to show it.

class _MockBatchProcessor extends Mock implements BatchProcessor {}

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockARNSRepository extends Mock implements ARNSRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// Discovery that answers with whatever the test set, and counts being asked.
/// The flag-off case turns entirely on [calls] staying empty.
class _SpyDiscovery implements DriveStateDiscovery {
  _SpyDiscovery();

  DriveStateDiscoveryResult Function() answer =
      () => const DriveStateDiscoveryResult.none();

  final calls =
      <({String driveId, String ownerAddress, int? minBlockHeight})>[];

  @override
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  }) async {
    calls.add((
      driveId: driveId,
      ownerAddress: ownerAddress,
      minBlockHeight: minBlockHeight,
    ));
    return answer();
  }
}

void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';

  /// The drive's watermark before this sync, and where the ordinary path would
  /// start from: the watermark less the look-back window.
  const localWatermark = 1000;
  const startsFromWithoutArtifact = localWatermark - kBlockHeightLookBack;

  /// Comfortably above the watermark, so the artifact has something to add.
  const artifactBlockEnd = 1500;
  const currentBlockHeight = 2000;
  const artifactTxId = 'artifact-tx-id';

  final codec = DriveStateEnvelopeCodec();

  late Wallet owner;
  late String ownerAddress;
  late SecretKey driveKey;

  /// The client that publishes: a drive with rows in it.
  late Database producerDb;

  /// The client that syncs.
  late Database db;

  late MockArweaveService arweave;
  late MockConfigService configService;
  late _MockUserPreferencesRepository userPreferences;
  late _SpyDiscovery discovery;
  late List<String> logged;
  late SyncRepository syncRepository;

  setUpAll(() async {
    // Two databases is the point - an artifact is written by one client and
    // read by another - and drift's warning about that is noise here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    owner = getTestWallet();
    ownerAddress = await owner.getAddress();
    driveKey = await AesGcm.with256bits().newSecretKey();
  });

  /// The private-drive protection, resolved the only way one can be.
  DriveStateProtection protectionFor(SecretKey key) =>
      DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.private,
        driveKey: key,
      ).protection!;

  final publicDrive = DriveStateProtection.forDrive(
    privacy: DrivePrivacyTag.public,
    driveKey: null,
  ).protection!;

  /// The artifact as it reaches sync: a body, and the tags an indexer reported.
  ///
  /// [blockEnd] moves the producer's own watermark before the export runs, so
  /// the signed coverage claim and the `Block-End` tag agree - which is what a
  /// real producer publishes, and what an importer requires. [tamperedTagBlockEnd]
  /// deliberately breaks that agreement, for the case where someone re-tags a
  /// genuine body.
  Future<({DriveStateArtifactCandidate candidate, Uint8List body})>
      sealArtifact({
    int blockEnd = artifactBlockEnd,
    int? tamperedTagBlockEnd,
    int? entityCount,
    SecretKey? sealedWith,
    DriveStateProtection? protection,
  }) async {
    await producerDb.driveDao.writeToDrive(DrivesCompanion(
      id: const Value(driveId),
      lastBlockHeight: Value(blockEnd),
    ));

    // A real artifact, built the way the producer builds one: a SQLite
    // database, not a serialisation of rows.
    final artifact = await sqlite.exportDriveState(
      producerDb,
      driveId: driveId,
      sink: await createArtifactSink('drive-state-sync'),
      blockEnd: blockEnd,
    );
    expect(artifact.blockEnd, blockEnd);

    final sealed = await codec.seal(
      plaintext: artifact.bytes,
      protection: protection ?? protectionFor(sealedWith ?? driveKey),
      wallet: owner,
    );
    expect(sealed.isSealed, isTrue, reason: sealed.toString());

    return (
      candidate: DriveStateArtifactCandidate(
        txId: artifactTxId,
        ownerAddress: ownerAddress,
        minedAtHeight: blockEnd,
        tags: {
          EntityTag.arFs: '0.15',
          EntityTag.entityType: EntityTypeTag.driveState,
          EntityTag.driveId: driveId,
          EntityTag.driveStateId: 'drive-state-id',
          EntityTag.stateVersion: currentVersionString,
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.blockStart: '0',
          EntityTag.blockEnd: '${tamperedTagBlockEnd ?? blockEnd}',
          EntityTag.entityCount: '${entityCount ?? artifact.entityCount}',
          // Written from what was sealed: a public drive's artifact carries
          // neither tag, and that absence is the discriminator.
          if (sealed.envelope!.isEncrypted) EntityTag.cipher: Cipher.aes256,
          if (sealed.envelope!.isEncrypted)
            EntityTag.cipherIv: sealed.envelope!.cipherIvAsBase64!,
        },
      ),
      body: sealed.envelope!.body,
    );
  }

  /// Puts an artifact where the sync will find it: discovered, and fetchable.
  Future<void> publish({
    int blockEnd = artifactBlockEnd,
    int? tamperedTagBlockEnd,
    int? entityCount,
    SecretKey? sealedWith,
    DriveStateProtection? protection,
  }) async {
    final artifact = await sealArtifact(
      blockEnd: blockEnd,
      tamperedTagBlockEnd: tamperedTagBlockEnd,
      entityCount: entityCount,
      sealedWith: sealedWith,
      protection: protection,
    );

    discovery.answer = () => DriveStateDiscoveryResult(
          candidates: [artifact.candidate],
        );

    when(() => arweave.getEntityDataFromNetwork(
          txId: artifactTxId,
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((_) async => artifact.body);
  }

  Future<List<SyncProgress>> sync({bool syncDeep = false}) => syncRepository
      .syncSingleDrive(driveId: driveId, syncDeep: syncDeep)
      .toList();

  /// Where the GraphQL pass actually started. The whole composition reduces to
  /// this number.
  int gqlStartedAt() {
    final call = verify(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          minBlockHeight: captureAny(named: 'minBlockHeight'),
          maxBlockHeight: captureAny(named: 'maxBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
          strategy: any(named: 'strategy'),
        ));
    expect(call.callCount, 1,
        reason: 'the GraphQL pass should run exactly '
            'once for a single contiguous range');
    return call.captured[0] as int;
  }

  /// Exactly the lines [DriveStateOutcomeReporter] writes for an outcome -
  /// the three sentences no note is allowed to contain.
  List<String> outcomeLines() => logged
      .where((m) =>
          m.contains('artifact used') ||
          m.contains('no artifact was used') ||
          m.contains('artifact rejected'))
      .toList();

  void expectExactlyOneOutcome(DriveStateOutcome outcome) {
    expect(outcomeLines(), hasLength(1), reason: 'logged: $logged');
    expect(outcomeLines().single, contains('outcome=${outcome.code}'));
  }

  Future<List<FileEntry>> fileRows() =>
      (db.select(db.fileEntries)..where((f) => f.driveId.equals(driveId)))
          .get();

  Future<List<FolderEntry>> folderRows() =>
      (db.select(db.folderEntries)..where((f) => f.driveId.equals(driveId)))
          .get();

  Future<Drive> driveRow() =>
      (db.select(db.drives)..where((d) => d.id.equals(driveId))).getSingle();

  void buildRepository({required bool enableSyncFromDriveState}) {
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      // The snapshot source is off so that the only thing that can move the
      // GraphQL range is the artifact.
      enableSyncFromSnapshot: false,
      enableSyncFromDriveState: enableSyncFromDriveState,
    ));

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: _MockBatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      arnsRepository: _MockARNSRepository(),
      userPreferencesRepository: userPreferences,
      driveStateSyncSource: DriveStateSyncSource(
        arweave: arweave,
        discovery: discovery,
        importer: DriveStateImporter(db.driveDao),
        reporter: DriveStateOutcomeReporter(
          sink: (_, message) => logged.add(message),
        ),
      ),
    );
  }

  setUp(() async {
    producerDb = getTestDb();
    db = getTestDb();
    discovery = _SpyDiscovery();
    logged = [];

    arweave = MockArweaveService();
    configService = MockConfigService();
    userPreferences = _MockUserPreferencesRepository();

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
    // `addTestFilesToDb` writes file revisions but no folder ones. The file
    // list joins entries through revisions, so this is a producer whose
    // folders all synced.
    await addFolderRevisionsToDb(
      producerDb,
      driveId: driveId,
      folderIds: [
        rootFolderId,
        nestedFolderId,
        'empty-nested-folder-id0',
      ],
    );
    await producerDb.driveDao.writeToDrive(DrivesCompanion(
      id: const Value(driveId),
      ownerAddress: Value(ownerAddress),
      privacy: const Value(DrivePrivacyTag.private),
      lastBlockHeight: const Value(artifactBlockEnd),
    ));

    // The drive as the syncing client already has it: attached, with its key,
    // and synced up to [localWatermark].
    await db.into(db.drives).insert(DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: ownerAddress,
          name: 'a-drive',
          privacy: DrivePrivacyTag.private,
          lastBlockHeight: const Value(localWatermark),
        ));
    // `DriveDao` starts its in-memory vaults from its constructor without
    // awaiting them; a test that reaches for one immediately loses that race.
    await db.driveDao.initVaults();
    await db.driveDao.putDriveKeyInMemory(
      driveID: driveId,
      driveKey: DriveKey(driveKey, false),
    );

    when(() => arweave.getCurrentBlockHeight())
        .thenAnswer((_) async => currentBlockHeight);
    when(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((_) => const Stream.empty());
    when(() => arweave.snapshotMetadataHits).thenReturn(<String, int>{});
    when(() => arweave.snapshotMetadataMisses).thenReturn(<String, int>{});
    when(() => arweave.clearUserDriveTxsCache()).thenReturn(null);
    when(() => userPreferences.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});
    when(() => userPreferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
      ),
    );

    buildRepository(enableSyncFromDriveState: false);
  });

  tearDown(() async {
    await db.close();
    await producerDb.close();
  });

  group('with the flag off', () {
    test('never asks whether the drive has an artifact', () async {
      await publish();

      await sync();

      expect(discovery.calls, isEmpty);
      expect(logged, isEmpty);
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
    });

    test('walks the whole range from the look-back, as it does today',
        () async {
      await publish();

      await sync();

      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expect(await fileRows(), isEmpty);
      expect(await folderRows(), isEmpty);
    });
  });

  group('with the flag on and an artifact that verifies', () {
    setUp(() => buildRepository(enableSyncFromDriveState: true));

    test('lands the drive\'s rows', () async {
      await publish();

      await sync();

      expect(await folderRows(), hasLength(3));
      expect(await fileRows(), hasLength(3));
      expect(
        (await folderRows()).map((f) => f.id),
        containsAll(<String>[rootFolderId, nestedFolderId]),
      );
      expectExactlyOneOutcome(DriveStateOutcome.used);
    });

    test('starts GraphQL above what the artifact covered', () async {
      await publish();

      await sync();

      expect(gqlStartedAt(), artifactBlockEnd);
      expect((await driveRow()).lastBlockHeight, artifactBlockEnd);
    });

    test('asks the indexer only about artifacts above the look-back', () async {
      await publish();

      await sync();

      expect(discovery.calls.single.minBlockHeight, startsFromWithoutArtifact);
      expect(discovery.calls.single.ownerAddress, ownerAddress);
    });

    test('never lets an artifact push the range past the current block',
        () async {
      // A *self-consistent* artifact claiming more than this node has seen:
      // signed coverage and tags agree, so the cross-check passes and the
      // clamp is the only thing left. Reachable without anyone lying - a
      // gateway lagging behind the producer answers a lower current height
      // than the producer legitimately synced to.
      //
      // The range below is `Range(start, currentBlockHeight)`, which throws
      // when start runs past end. An over-large claim may cost a wasted
      // download; it may not fail the drive.
      await publish(blockEnd: currentBlockHeight + 100000);

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(gqlStartedAt(), currentBlockHeight);
    });

    test('refuses a genuine body wearing someone else\'s Block-End', () async {
      // The tag is what an indexer reports and nobody signs; the coverage
      // claim is inside the sealed payload. Re-tagging a real artifact to
      // claim a higher range would walk the watermark across blocks whose
      // rows it never carried, which is the silent drop this artifact format
      // exists to avoid. The body is the owner's, correctly sealed - only the
      // tag is wrong.
      await publish(tamperedTagBlockEnd: currentBlockHeight - 1);

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      // Not the artifact's range, and not the tampered one: the ordinary
      // starting point for a drive with no usable artifact.
      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expect((await driveRow()).lastBlockHeight, isNot(currentBlockHeight - 1));
    });
  });

  group('with the flag on and an artifact that does not verify', () {
    setUp(() => buildRepository(enableSyncFromDriveState: true));

    test('syncs the ordinary way when there is no artifact to find', () async {
      await sync();

      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expectExactlyOneOutcome(DriveStateOutcome.noneFound);
      expect(await fileRows(), isEmpty);
    });

    test('syncs the ordinary way when the payload will not decrypt', () async {
      await publish(sealedWith: await AesGcm.with256bits().newSecretKey());

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expectExactlyOneOutcome(DriveStateOutcome.decryptFailed);
      expect(await fileRows(), isEmpty);
      expect((await driveRow()).lastBlockHeight, localWatermark);
    });

    test('syncs the ordinary way when Entity-Count disagrees', () async {
      await publish(entityCount: 99);

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expectExactlyOneOutcome(DriveStateOutcome.countMismatch);
      // The count is checked before the first write, so a payload that fails
      // it leaves nothing behind.
      expect(await fileRows(), isEmpty);
      expect(await folderRows(), isEmpty);
    });

    test('syncs the ordinary way when the body cannot be fetched', () async {
      await publish();
      when(() => arweave.getEntityDataFromNetwork(
            txId: artifactTxId,
            largeBody: any(named: 'largeBody'),
          )).thenThrow(Exception('the gateway is down'));

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expect(await fileRows(), isEmpty);
    });

    test('does not fail the drive when the artifact path throws', () async {
      discovery.answer = () => throw StateError('the indexer exploded');

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(progress.last.errorMessages, isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
      expectExactlyOneOutcome(DriveStateOutcome.integrityFailed);
    });
  });

  /// A deep sync is the app's only "start over" remedy — offered from the top
  /// bar, from two places on the drive detail page, and from the explorer's
  /// item menu — and it means *distrust what is local and rebuild this drive
  /// from the chain*. An artifact is local state, just someone else's, so a
  /// deep sync that read one would answer the request by starting from a
  /// stranger's copy of where the drive already was.
  ///
  /// The flag being on made that the remedy's behaviour: `syncDeep` passes
  /// `lastBlockHeight: 0`, which exempts nothing on its own — discovery still
  /// runs, the artifact still imports, and `[0, tip]` still collapses to
  /// `[Block-End, tip]`. A user whose drive looked wrong because of an
  /// artifact would have had no way out from inside the app.
  group('a deep sync', () {
    setUp(() => buildRepository(enableSyncFromDriveState: true));

    test('never asks whether the drive has an artifact', () async {
      await publish();

      final progress = await sync(syncDeep: true);

      expect(progress.last.failedDriveIds, isEmpty);
      expect(discovery.calls, isEmpty);
      expect(outcomeLines(), isEmpty);
      verifyNever(() => arweave.getEntityDataFromNetwork(
            txId: any(named: 'txId'),
            largeBody: any(named: 'largeBody'),
          ));
    });

    test('walks the whole range from the beginning of the drive', () async {
      await publish();

      await sync(syncDeep: true);

      expect(
        gqlStartedAt(),
        0,
        reason: 'a deep sync asked for [0, tip]; an artifact that moved the '
            'start to its Block-End would re-apply whatever the user is '
            'trying to undo',
      );
      expect(await fileRows(), isEmpty);
      expect(await folderRows(), isEmpty);
    });

    test('an ordinary sync of the same drive still uses the artifact',
        () async {
      // The control. Without it the two tests above would pass just as
      // happily against a flag that was simply off.
      await publish();

      await sync();

      expect(discovery.calls, hasLength(1));
      expect(gqlStartedAt(), artifactBlockEnd);
    });

    test('is exempt through syncAllDrives too, not just syncSingleDrive',
        () async {
      // Both deep entry points reach `_syncDrive` by different routes, and
      // `startSync(deepSync: true)` — the top bar's — is this one.
      await publish();

      try {
        await syncRepository.syncAllDrives(syncDeep: true).toList();
      } catch (_) {
        // The post-sync phase of a full sync wants more of the app than this
        // harness stands up. The drive itself has already been synced by the
        // time it runs, which is what these assertions are about.
      }

      expect(discovery.calls, isEmpty);
      expect(gqlStartedAt(), 0);
    });
  });

  /// A public drive, which used to be skipped here entirely.
  ///
  /// The gate was `driveKey == null`, and a public drive and a private drive
  /// whose key had gone missing arrive at it identically. Now the drive row's
  /// own privacy decides, so the two are told apart: one reads an artifact,
  /// the other does not.
  group('a public drive', () {
    setUp(() async {
      buildRepository(enableSyncFromDriveState: true);
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
        encryptedKey: Value(null),
        keyEncryptionIv: Value(null),
        driveKeyGenerated: Value(false),
      ));
      await producerDb.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
      ));
    });

    Future<void> publishPublicly({int blockEnd = artifactBlockEnd}) =>
        publish(blockEnd: blockEnd, protection: publicDrive);

    test('is asked about, with no key needed to ask', () async {
      await publishPublicly();

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(discovery.calls, hasLength(1));
      expectExactlyOneOutcome(DriveStateOutcome.used);
    });

    test('lands the drive\'s rows', () async {
      await publishPublicly();
      await sync();

      expect(await fileRows(), hasLength(3));
      expect(await folderRows(), hasLength(3));
      expect((await driveRow()).lastBlockHeight, artifactBlockEnd);
      expect((await driveRow()).privacy, DrivePrivacyTag.public);
    });

    test('starts GraphQL above what the artifact covered', () async {
      await publishPublicly();
      await sync();

      expect(gqlStartedAt(), artifactBlockEnd);
    });

    test('rejects an encrypted artifact offered to it', () async {
      // Sealed the private way and tagged accordingly, which is exactly what
      // a producer that mistook this drive for a private one would publish.
      await publish(protection: protectionFor(driveKey));

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expectExactlyOneOutcome(DriveStateOutcome.privacyMismatch);
      expect(await fileRows(), isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
    });
  });

  /// The half of the old `driveKey == null` gate that still has to hold.
  ///
  /// A private drive with no key must not read an artifact - there is nothing
  /// to open one with, and the plaintext chain is not an alternative. The way
  /// in is a drive row that is private and carries no `encryptedKey`, which is
  /// what `DriveDao.getDriveKey` hands back null for.
  group('a private drive whose key cannot be found', () {
    setUp(() async {
      buildRepository(enableSyncFromDriveState: true);
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.private),
        encryptedKey: Value(null),
        keyEncryptionIv: Value(null),
        driveKeyGenerated: Value(false),
      ));
    });

    test('is never asked about, and the sync walks the range itself', () async {
      await publish();

      // A cipher key is supplied, so `getDriveKey` is the path taken - and it
      // returns null, because there is no wrapped drive key to unwrap.
      final progress = await syncRepository
          .syncSingleDrive(driveId: driveId, cipherKey: driveKey)
          .toList();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(discovery.calls, isEmpty,
          reason: 'a private drive with no key has nothing to open an '
              'artifact with, so it must not even look for one');
      expect(await fileRows(), isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
    });

    test('produces no outcome, because no artifact was ever identified',
        () async {
      await publish();

      await syncRepository
          .syncSingleDrive(driveId: driveId, cipherKey: driveKey)
          .toList();

      // §7 gives an outcome to an artifact, and nothing here reached one.
      // The reason is written to the app logger under the `[drive-state]`
      // prefix, the same way the deep-sync exemption is; neither is visible
      // through the reporter's sink, which is what `logged` collects.
      expect(outcomeLines(), isEmpty);
      expect(logged, isEmpty);
    });
  });
}
