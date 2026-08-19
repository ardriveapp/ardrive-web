import 'dart:convert';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/core/crypto/crypto.dart' show DriveKey;
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/data/drive_state_export.dart';
import 'package:ardrive/drive_state/data/drive_state_import.dart';
import 'package:ardrive/drive_state/data/drive_state_sync_source.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_outcome.dart';
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

  final calls = <({String driveId, String ownerAddress, int? minBlockHeight})>[];

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

  /// The artifact as it reaches sync: a body, and the tags an indexer reported.
  Future<({DriveStateArtifactCandidate candidate, Uint8List body})> sealArtifact({
    int blockEnd = artifactBlockEnd,
    int? entityCount,
    SecretKey? sealedWith,
  }) async {
    final export = await exportDriveState(producerDb.driveDao, driveId);
    final payload = utf8.encode(jsonEncode(export.toJson()));

    final sealed = await codec.seal(
      plaintext: Uint8List.fromList(payload),
      driveKey: sealedWith ?? driveKey,
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
          EntityTag.stateVersion: '1',
          EntityTag.contentType: ContentType.octetStream,
          EntityTag.contentEncoding: ContentEncodingTag.gzip,
          EntityTag.blockStart: '0',
          EntityTag.blockEnd: '$blockEnd',
          EntityTag.entityCount: '${entityCount ?? export.entityCount}',
          EntityTag.cipher: Cipher.aes256,
          EntityTag.cipherIv: sealed.envelope!.cipherIvAsBase64,
        },
      ),
      body: sealed.envelope!.body,
    );
  }

  /// Puts an artifact where the sync will find it: discovered, and fetchable.
  Future<void> publish({
    int blockEnd = artifactBlockEnd,
    int? entityCount,
    SecretKey? sealedWith,
  }) async {
    final artifact = await sealArtifact(
      blockEnd: blockEnd,
      entityCount: entityCount,
      sealedWith: sealedWith,
    );

    discovery.answer = () => DriveStateDiscoveryResult(
          candidates: [artifact.candidate],
        );

    when(() => arweave.getEntityDataFromNetwork(
          txId: artifactTxId,
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((_) async => artifact.body);
  }

  Future<List<SyncProgress>> sync() =>
      syncRepository.syncSingleDrive(driveId: driveId).toList();

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
    expect(call.callCount, 1, reason: 'the GraphQL pass should run exactly '
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
      (db.select(db.fileEntries)..where((f) => f.driveId.equals(driveId))).get();

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
      // `Block-End` is a tag on a transaction nobody has to trust, and the
      // range below is `Range(start, currentBlockHeight)` - which throws when
      // start runs past end. A lying tag may cost a wasted download; it may
      // not fail the drive.
      await publish(blockEnd: currentBlockHeight + 100000);

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(gqlStartedAt(), currentBlockHeight);
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

  group('a public drive', () {
    setUp(() async {
      buildRepository(enableSyncFromDriveState: true);
      await db.driveDao.writeToDrive(const DrivesCompanion(
        id: Value(driveId),
        privacy: Value(DrivePrivacyTag.public),
      ));
    });

    test('is not asked about, because v1 is private only', () async {
      await publish();

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(discovery.calls, isEmpty);
      expect(logged, isEmpty);
      expect(gqlStartedAt(), startsFromWithoutArtifact);
    });
  });
}
