import 'dart:convert';

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
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/constants.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart'
    show SnapshotItem, DriveHistoryTransaction;
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

/// All three of a drive's history sources at once: the artifact, then
/// snapshots, then GraphQL (`docs/DRIVE_STATE_ARTIFACT.md` §5).
///
/// `sync_repository_drive_state_test.dart` proves the artifact in isolation
/// and turns the snapshot source *off* on purpose, so that nothing but the
/// artifact can move the GraphQL range. That isolation is worth keeping and is
/// not touched here. This file is the other half: both sources live, which is
/// the configuration a drive with existing snapshots actually runs.
///
/// What is asserted is the arithmetic between them - which blocks each source
/// is left responsible for. A gap between two sources is a permanent silent
/// drop; an overlap is only wasted time. So the assertions are on the exact
/// ranges the GraphQL pass is asked for, not merely on rows landing.
///
/// Everything below the seam is real: two real databases, a real export, a
/// real seal, the real importer, the real `HeightRange` arithmetic, a real
/// `BatchProcessor` and the real revision/entry writers. Stood in for are the
/// gateway, the indexer that answers a discovery query, and the metadata
/// decode - the three things a test cannot have.

class _MockARNSRepository extends Mock implements ARNSRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// Discovery that answers with whatever the test set, and counts being asked.
class _SpyDiscovery implements DriveStateDiscovery {
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

/// Validation that accepts everything and remembers what it was handed.
///
/// Accepting everything keeps the range arithmetic - the thing under test -
/// the only reason a snapshot can fail to contribute. The record is itself an
/// assertion target: each item here costs a network probe against the gateway,
/// so a snapshot that reaches this list and then contributes no blocks is
/// measurable waste.
class _AcceptingValidation implements SnapshotValidationService {
  final asked = <String>[];

  @override
  Future<List<SnapshotItem>> validateSnapshotItems(
    List<SnapshotItem> snapshotItems,
  ) async {
    asked.addAll(snapshotItems.map((i) => i.txId));
    return snapshotItems;
  }
}

/// A transaction the sync will meet, wherever it reaches it from.
class _PlantedTx {
  const _PlantedTx({required this.fileId, required this.height});

  final String fileId;
  final int height;

  String get txId => 'tx-$fileId';
}

/// A snapshot as the gateway reports it, plus the body it serves.
class _SnapshotFixture {
  const _SnapshotFixture({
    required this.txId,
    required this.blockStart,
    required this.blockEnd,
    required this.minedAt,
    required this.contains,
  });

  final String txId;
  final int blockStart;
  final int blockEnd;

  /// The block the snapshot transaction itself landed in. The gateway query
  /// filters on this (`block: {min: ...}`), not on the covered range.
  final int minedAt;

  /// The entity transactions inside the body.
  final List<_PlantedTx> contains;
}

void main() {
  const driveId = 'drive-id';
  const rootFolderId = 'root-folder-id';
  const nestedFolderId = 'nested-folder-id';

  /// The drive's watermark before this sync, and where the ordinary path would
  /// start from: the watermark less the look-back window.
  const localWatermark = 1000;
  const startsFromWithoutArtifact = localWatermark - kBlockHeightLookBack;

  /// `B` in the notes below: the last block the artifact accounts for.
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
  late _AcceptingValidation validation;
  late SyncRepository syncRepository;
  late List<String> logged;

  /// Bodies the fake gateway will serve, by transaction id: snapshots and the
  /// artifact both arrive through `getEntityDataFromNetwork`.
  late Map<String, Uint8List> bodies;

  /// Snapshots the indexer knows about.
  late List<_SnapshotFixture> publishedSnapshots;

  /// Whether the fake gateway applies the query's own `block: {min}` filter.
  ///
  /// True is the single-drive path, where the min is this drive's own start
  /// height. False is the batched prefetch in `syncAllDrives`, which asks once
  /// per owner with the *lowest* start height across their drives and hands
  /// every result to every drive - so a drive can be handed snapshots from far
  /// below its own start.
  late bool gatewayHonoursMinBlockHeight;

  /// Every `minBlockHeight` the snapshot query was asked with.
  late List<int?> snapshotQueryMins;

  /// Transactions the GraphQL pass will find, if it asks for their block.
  late List<_PlantedTx> plantedInGql;

  /// Every transaction id handed to the parse stage, in order and with
  /// repeats. This is where "covered exactly once" stops being arithmetic
  /// about ranges and becomes a count of deliveries.
  late List<String> deliveredTxIds;

  Map<String, dynamic> nodeJson(_PlantedTx tx) => {
        'id': tx.txId,
        'bundledIn': {'id': 'bundle-id'},
        'owner': {'address': ownerAddress},
        'tags': [
          {'name': EntityTag.driveId, 'value': driveId},
          {'name': EntityTag.entityType, 'value': EntityTypeTag.file},
        ],
        'block': {'height': tx.height, 'timestamp': tx.height * 100},
      };

  DriveEntityHistoryTransactionModel gqlModel(_PlantedTx tx) =>
      DriveEntityHistoryTransactionModel(
        transactionCommonMixin: DriveHistoryTransaction.fromJson(nodeJson(tx)),
      );

  setUpAll(() async {
    // Two databases is the point - an artifact is written by one client and
    // read by another - and drift's warning about that is noise here.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

    owner = getTestWallet();
    ownerAddress = await owner.getAddress();
    driveKey = await AesGcm.with256bits().newSecretKey();
  });

  /// The artifact as it reaches sync: a body, and the tags an indexer reported.

  /// The private-drive protection, resolved the only way one can be.
  DriveStateProtection protectionFor(SecretKey key) =>
      DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.private,
        driveKey: key,
      ).protection!;

  Future<void> publishArtifact({
    int blockEnd = artifactBlockEnd,
    SecretKey? sealedWith,
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
      sink: await createArtifactSink('composition'),
      blockEnd: blockEnd,
    );
    expect(artifact.blockEnd, blockEnd);

    final sealed = await codec.seal(
      plaintext: artifact.bytes,
      protection: protectionFor(sealedWith ?? driveKey),
      wallet: owner,
    );
    expect(sealed.isSealed, isTrue, reason: sealed.toString());

    discovery.answer = () => DriveStateDiscoveryResult(
          candidates: [
            DriveStateArtifactCandidate(
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
                EntityTag.blockEnd: '$blockEnd',
                EntityTag.entityCount: '${artifact.entityCount}',
                EntityTag.cipher: Cipher.aes256,
                EntityTag.cipherIv: sealed.envelope!.cipherIvAsBase64!,
              },
            ),
          ],
        );

    bodies[artifactTxId] = sealed.envelope!.body;
  }

  /// Puts a snapshot where the sync will find it, with a body it can read.
  void publishSnapshot(_SnapshotFixture fixture) {
    publishedSnapshots.add(fixture);
    bodies[fixture.txId] = Uint8List.fromList(utf8.encode(jsonEncode({
      'txSnapshots': [
        for (final tx in fixture.contains)
          {
            'gqlNode': nodeJson(tx),
            'jsonMetadata': '{"name": "${tx.fileId}"}',
          },
      ],
    })));
  }

  Future<List<SyncProgress>> sync() =>
      syncRepository.syncSingleDrive(driveId: driveId).toList();

  /// Every range the GraphQL pass was asked for, in ascending order.
  ///
  /// `verify` consumes the recorded calls, so this is called once per test.
  List<Range> gqlRanges() {
    final captured = verify(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          minBlockHeight: captureAny(named: 'minBlockHeight'),
          maxBlockHeight: captureAny(named: 'maxBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
          strategy: any(named: 'strategy'),
        )).captured;

    final ranges = <Range>[];
    for (var i = 0; i < captured.length; i += 2) {
      ranges.add(Range(
        start: captured[i] as int,
        end: captured[i + 1] as int,
      ));
    }
    return ranges..sort((a, b) => a.start - b.start);
  }

  /// The blocks covered more than once by [ranges], having first asserted that
  /// together they leave no gap between [from] and [to].
  ///
  /// A gap is the failure that matters: no source is responsible for those
  /// blocks, and nothing later goes looking for them, so whatever was in them
  /// is dropped for good. An overlap only costs time, so it is returned rather
  /// than failed on, and each test says which overlap it expects.
  Set<int> overlapsWithNoGaps(
    List<Range> ranges, {
    required int from,
    required int to,
  }) {
    final seen = <int, int>{};
    for (final range in ranges) {
      for (var block = range.start; block <= range.end; block++) {
        seen[block] = (seen[block] ?? 0) + 1;
      }
    }

    final uncovered = [
      for (var block = from; block <= to; block++)
        if (!seen.containsKey(block)) block,
    ];
    expect(uncovered, isEmpty,
        reason: 'blocks no source was made responsible for: '
            '${uncovered.take(20)} (of ${uncovered.length}); ranges: $ranges');

    return {
      for (final entry in seen.entries)
        if (entry.value > 1) entry.key,
    };
  }

  List<String> outcomeLines() => logged
      .where((m) =>
          m.contains('artifact used') ||
          m.contains('no artifact was used') ||
          m.contains('artifact rejected'))
      .toList();

  Future<Set<String>> fileIds() async => (await (db.select(db.fileEntries)
            ..where((f) => f.driveId.equals(driveId)))
          .get())
      .map((f) => f.id)
      .toSet();

  void buildRepository({required bool enableSyncFromDriveState}) {
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      // Both sources live. This is the whole point of the file.
      enableSyncFromSnapshot: true,
      enableSyncFromDriveState: enableSyncFromDriveState,
    ));

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: BatchProcessor(),
      snapshotValidationService: validation,
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
    validation = _AcceptingValidation();
    logged = [];
    bodies = {};
    publishedSnapshots = [];
    plantedInGql = [];
    deliveredTxIds = [];
    snapshotQueryMins = [];
    gatewayHonoursMinBlockHeight = true;

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
    await addFolderRevisionsToDb(
      producerDb,
      driveId: driveId,
      folderIds: [rootFolderId, nestedFolderId, 'empty-nested-folder-id0'],
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
    await db.driveDao.initVaults();
    await db.driveDao.putDriveKeyInMemory(
      driveID: driveId,
      driveKey: DriveKey(driveKey, false),
    );

    when(() => arweave.getCurrentBlockHeight())
        .thenAnswer((_) async => currentBlockHeight);

    // The gateway serves whatever has been published, and nothing else.
    when(() => arweave.getEntityDataFromNetwork(
          txId: any(named: 'txId'),
          largeBody: any(named: 'largeBody'),
        )).thenAnswer((invocation) async {
      final txId = invocation.namedArguments[#txId] as String;
      final body = bodies[txId];
      if (body == null) {
        throw StateError('nothing published at $txId');
      }
      return body;
    });

    // The snapshot index, in HEIGHT_DESC as the real query returns it.
    when(() => arweave.getAllSnapshotsOfDrive(
          any(),
          any(),
          ownerAddress: any(named: 'ownerAddress'),
        )).thenAnswer((invocation) {
      final min = invocation.positionalArguments[1] as int?;
      snapshotQueryMins.add(min);

      final visible = publishedSnapshots
          .where((s) =>
              !gatewayHonoursMinBlockHeight || min == null || s.minedAt >= min)
          .toList()
        ..sort((a, b) => b.minedAt - a.minedAt);

      return Stream.fromIterable(visible.map(
        (s) => SnapshotEntityTransaction.fromJson({
          'id': s.txId,
          'bundledIn': {'id': 'bundle-id'},
          'owner': {'address': ownerAddress},
          'tags': [
            {'name': 'Block-Start', 'value': '${s.blockStart}'},
            {'name': 'Block-End', 'value': '${s.blockEnd}'},
            {'name': 'Drive-Id', 'value': driveId},
            {'name': EntityTag.entityType, 'value': EntityTypeTag.snapshot},
          ],
          'block': {'height': s.minedAt, 'timestamp': s.minedAt * 100},
        }),
      ));
    });

    // The GraphQL pass finds only what was planted inside the range it asked
    // for - so a range never asked for is a transaction never seen.
    when(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((invocation) {
      final min = invocation.namedArguments[#minBlockHeight] as int;
      final max = invocation.namedArguments[#maxBlockHeight] as int;
      final found = plantedInGql
          .where((t) => t.height >= min && t.height <= max)
          .map(gqlModel)
          .toList();
      return found.isEmpty
          ? const Stream<List<DriveEntityHistoryTransactionModel>>.empty()
          : Stream.value(found);
    });

    // The metadata decode, which needs a gateway and a cipher. Every
    // transaction that reaches this point becomes the file it stands for, so
    // a file in the database is proof its transaction was actually delivered
    // by one of the three sources.
    when(() => arweave.createDriveEntityHistoryFromTransactions(
          any(),
          any(),
          any(),
          driveId: any(named: 'driveId'),
          ownerAddress: any(named: 'ownerAddress'),
          currentBlockHeight: any(named: 'currentBlockHeight'),
        )).thenAnswer((invocation) async {
      final txs = invocation.positionalArguments[0]
          as List<DriveEntityHistoryTransactionModel>;
      final known = {
        for (final tx in [
          ...plantedInGql,
          ...publishedSnapshots.expand((s) => s.contains),
        ])
          tx.txId: tx,
      };

      final blocks = <BlockEntities>[];
      for (final tx in txs) {
        deliveredTxIds.add(tx.transactionCommonMixin.id);
        final planted = known[tx.transactionCommonMixin.id];
        if (planted == null) continue;
        final height = tx.transactionCommonMixin.block?.height ?? 0;
        if (blocks.isEmpty || blocks.last.blockHeight != height) {
          blocks.add(BlockEntities(height));
        }
        blocks.last.entities.add(FileEntity(
          id: planted.fileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: planted.fileId,
          size: 100,
          lastModifiedDate:
              DateTime.fromMillisecondsSinceEpoch(planted.height * 1000),
          dataTxId: '${planted.txId}-data',
          dataContentType: 'application/octet-stream',
        )
          ..txId = planted.txId
          ..ownerAddress = ownerAddress
          ..createdAt =
              DateTime.fromMillisecondsSinceEpoch(planted.height * 1000));
      }
      return DriveEntityHistory(null, blocks);
    });

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

    buildRepository(enableSyncFromDriveState: true);
  });

  tearDown(() async {
    await db.close();
    await producerDb.close();
  });

  group('an artifact and snapshots above it', () {
    // The artifact covers [0, 1500]; one snapshot covers [1600, 1700]; the
    // tip is 2000. Nothing but GraphQL can account for 1501-1599 or
    // 1701-2000.
    const inSnapshot = _PlantedTx(fileId: 'file-from-snapshot', height: 1650);
    const inGql = _PlantedTx(fileId: 'file-from-gql', height: 1900);

    setUp(() async {
      await publishArtifact();
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-above',
        blockStart: 1600,
        blockEnd: 1700,
        minedAt: 1705,
        contains: [inSnapshot],
      ));
      plantedInGql.add(inGql);
    });

    test('leaves GraphQL exactly the blocks neither of the other two covered',
        () async {
      await sync();

      expect(
        gqlRanges(),
        [Range(start: 1500, end: 1599), Range(start: 1701, end: 2000)],
        reason: 'the artifact covered through 1500 and the snapshot 1600-1700',
      );
    });

    test('covers every block from the drive\'s start to the tip', () async {
      await sync();

      // The artifact's claim and the snapshot's claim are what the fixture
      // published; the GraphQL ranges are what the code actually asked for.
      final overlaps = overlapsWithNoGaps(
        [
          Range(start: 0, end: artifactBlockEnd),
          Range(start: 1600, end: 1700),
          ...gqlRanges(),
        ],
        from: 0,
        to: currentBlockHeight,
      );

      // `Range` is inclusive at both ends, and the GraphQL range is built as
      // `Range(start: syncFromBlockHeight, ...)` - so block 1500 is both the
      // last block the artifact covered and the first the GraphQL pass is
      // asked for. One block re-walked, in line with the look-back the
      // ordinary path already applies, and idempotent: the revision writers
      // find the rows already present and record nothing.
      expect(overlaps, {artifactBlockEnd});
    });

    test('lands a file from each of the three sources', () async {
      await sync();

      expect(
        await fileIds(),
        {
          // The artifact's, from the producer's database.
          '${rootFolderId}0',
          '${rootFolderId}1',
          '${nestedFolderId}0',
          inSnapshot.fileId,
          inGql.fileId,
        },
      );
      expect(outcomeLines().single,
          contains('outcome=${DriveStateOutcome.used.code}'));
    });

    test('narrows the snapshot search to what the artifact left', () async {
      await sync();

      expect(snapshotQueryMins, [artifactBlockEnd],
          reason: 'without the artifact this drive would have asked from '
              '$startsFromWithoutArtifact');
    });
  });

  group('a snapshot that straddles the artifact\'s last block', () {
    // The case with the most room to be wrong: [1400, 1600] against an
    // artifact covering [0, 1500]. Either the half above 1500 is still used,
    // or the snapshot is dropped whole and 1501-1600 falls through to
    // GraphQL (correct but slow) or to nothing at all (a hole).
    const aboveTheBoundary =
        _PlantedTx(fileId: 'file-above-boundary', height: 1550);
    const belowTheBoundary =
        _PlantedTx(fileId: 'file-below-boundary', height: 1450);

    setUp(() async {
      await publishArtifact();
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-straddling',
        blockStart: 1400,
        blockEnd: 1600,
        minedAt: 1605,
        contains: [belowTheBoundary, aboveTheBoundary],
      ));
    });

    test('keeps the half above the boundary and does not re-walk it', () async {
      await sync();

      expect(
        gqlRanges(),
        [Range(start: 1500, end: 1500), Range(start: 1601, end: 2000)],
        reason: 'the snapshot was kept and obscured 1501-1600; had it been '
            'dropped whole, GraphQL would have been asked for 1500-2000',
      );
    });

    test('serves the entity above the boundary from the snapshot', () async {
      await sync();

      expect(await fileIds(), contains(aboveTheBoundary.fileId));
    });

    test(
        'does not serve the half below the boundary, which is the '
        'artifact\'s to account for', () async {
      await sync();

      // Not a hole. The artifact's signed claim is that every entity through
      // block 1500 is already in the database, so the snapshot re-serving
      // 1400-1500 would be duplicate work, and the GraphQL pass not being
      // asked for it is the saving the artifact exists to make. The file is
      // absent here only because this fixture put it in the snapshot and not
      // in the artifact.
      expect(await fileIds(), isNot(contains(belowTheBoundary.fileId)));
    });

    test('leaves no block between the artifact and the tip unaccounted for',
        () async {
      await sync();

      final overlaps = overlapsWithNoGaps(
        [
          Range(start: 0, end: artifactBlockEnd),
          // What the snapshot was actually left responsible for: its own
          // range less the artifact's.
          Range(start: 1501, end: 1600),
          ...gqlRanges(),
        ],
        from: 0,
        to: currentBlockHeight,
      );

      // Again only the boundary block itself - but here it costs a whole
      // GraphQL round trip of its own for one already-covered block. Cheap,
      // and the same overlap the ordinary look-back path has always had, but
      // worth naming.
      expect(overlaps, {artifactBlockEnd});
    });
  });

  group('a snapshot that starts exactly where the artifact ends', () {
    setUp(() async {
      await publishArtifact();
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-abutting',
        blockStart: artifactBlockEnd,
        blockEnd: 1600,
        minedAt: 1605,
        contains: [],
      ));
    });

    test('does not have both of them serve the shared block', () async {
      await sync();

      // `Range` is inclusive at both ends, so an artifact through 1500 and a
      // snapshot from 1500 both name block 1500. The snapshot yields: the
      // obscuring accumulator is seeded with [0, 1500], so the snapshot is
      // left 1501-1600 and block 1500 is not read from it.
      expect(
        gqlRanges(),
        [Range(start: 1500, end: 1500), Range(start: 1601, end: 2000)],
      );
    });
  });

  group('a snapshot entirely below what the artifact covers', () {
    setUp(() => publishArtifact());

    test('is never asked for on the single-drive path', () async {
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-below',
        blockStart: 900,
        blockEnd: 1100,
        minedAt: 1105,
        contains: [],
      ));

      await sync();

      // The query's own `block: {min}` filter does the work: the min is the
      // artifact's last block, and this snapshot was mined below it.
      expect(snapshotQueryMins, [artifactBlockEnd]);
      expect(validation.asked, isEmpty);
      expect(gqlRanges(), [Range(start: 1500, end: 2000)]);
    });

    test('contributes nothing when the batched prefetch hands one over',
        () async {
      // `syncAllDrives` asks once per owner using the lowest start height
      // across their drives, so a drive whose artifact moved it far ahead is
      // handed snapshots chosen for a different drive.
      gatewayHonoursMinBlockHeight = false;
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-below',
        blockStart: 900,
        blockEnd: 1100,
        minedAt: 1105,
        contains: [_PlantedTx(fileId: 'file-below-artifact', height: 1000)],
      ));

      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      // It obscures nothing, so the GraphQL range is exactly what it would
      // have been with no snapshot at all - correct, and no gap.
      expect(gqlRanges(), [Range(start: 1500, end: 2000)]);
      expect(await fileIds(), isNot(contains('file-below-artifact')));
    });

    test('is not probed over the network, since it can serve no block',
        () async {
      // Validation is a HEAD against the gateway per snapshot, retried up to
      // four times over roughly fifty seconds before it gives up. Spending
      // that on a snapshot whose every block is already accounted for buys
      // nothing: an item with no sub-ranges is never read from, so whether it
      // is reachable cannot change this sync.
      gatewayHonoursMinBlockHeight = false;
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-below',
        blockStart: 900,
        blockEnd: 1100,
        minedAt: 1105,
        contains: [],
      ));
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-above',
        blockStart: 1600,
        blockEnd: 1700,
        minedAt: 1705,
        contains: [],
      ));

      await sync();

      expect(validation.asked, ['snapshot-above'],
          reason: 'the one below the artifact can serve no block');
      expect(
        gqlRanges(),
        [Range(start: 1500, end: 1599), Range(start: 1701, end: 2000)],
        reason: 'dropping it must not change what anything else is asked for',
      );
    });
  });

  group('two snapshots that overlap each other, above an artifact', () {
    // A real drive accumulates snapshots, and later ones re-cover ground
    // earlier ones already hold. The accumulator runs newest-first - the
    // query sorts HEIGHT_DESC - so the newer keeps the shared band and the
    // older is left only the part below it.
    //
    // Artifact [0, 1500]; newer snapshot [1650, 1800]; older [1600, 1700].
    // The older should keep 1600-1649 and nothing more.
    const onlyInOlder = _PlantedTx(fileId: 'file-only-in-older', height: 1620);
    const inBoth = _PlantedTx(fileId: 'file-in-both', height: 1680);
    const onlyInNewer = _PlantedTx(fileId: 'file-only-in-newer', height: 1750);

    setUp(() async {
      await publishArtifact();
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-older',
        blockStart: 1600,
        blockEnd: 1700,
        minedAt: 1705,
        contains: [onlyInOlder, inBoth],
      ));
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-newer',
        blockStart: 1650,
        blockEnd: 1800,
        minedAt: 1805,
        contains: [inBoth, onlyInNewer],
      ));
    });

    test('splits the shared band between them rather than dropping either',
        () async {
      await sync();

      // 1600-1800 is covered by the two together, so GraphQL gets only what
      // is outside them. If the older had been dropped for overlapping,
      // 1600-1649 would appear here.
      expect(
        gqlRanges(),
        [Range(start: 1500, end: 1599), Range(start: 1801, end: 2000)],
      );
      expect(validation.asked, ['snapshot-newer', 'snapshot-older'],
          reason: 'both still serve blocks, so both are worth probing');
    });

    test('delivers the transaction they both hold exactly once', () async {
      await sync();

      expect(
        deliveredTxIds.where((id) => id == inBoth.txId),
        hasLength(1),
        reason: 'block 1680 falls in the newer snapshot\'s band; the older '
            'skips it rather than serving it a second time',
      );
      expect(await fileIds(),
          containsAll([onlyInOlder.fileId, inBoth.fileId, onlyInNewer.fileId]));
    });

    test('leaves no block between the artifact and the tip unaccounted for',
        () async {
      await sync();

      final overlaps = overlapsWithNoGaps(
        [
          Range(start: 0, end: artifactBlockEnd),
          // What each snapshot was actually left responsible for.
          Range(start: 1600, end: 1649),
          Range(start: 1650, end: 1800),
          ...gqlRanges(),
        ],
        from: 0,
        to: currentBlockHeight,
      );
      expect(overlaps, {artifactBlockEnd});
    });
  });

  group('an artifact that does not verify', () {
    // §2.5: every failure in the artifact path is a fallback. The one that
    // matters here is that falling back reaches the *snapshot* source in
    // working order, not just GraphQL.
    const inSnapshot = _PlantedTx(fileId: 'file-from-snapshot', height: 1650);

    setUp(() async {
      await publishArtifact(
        sealedWith: await AesGcm.with256bits().newSecretKey(),
      );
      publishSnapshot(const _SnapshotFixture(
        txId: 'snapshot-above',
        blockStart: 1600,
        blockEnd: 1700,
        minedAt: 1705,
        contains: [inSnapshot],
      ));
    });

    test('still lets the snapshots do their job', () async {
      final progress = await sync();

      expect(progress.last.failedDriveIds, isEmpty);
      expect(outcomeLines().single,
          contains('outcome=${DriveStateOutcome.decryptFailed.code}'));

      // The whole range from the ordinary look-back, less the snapshot's.
      expect(
        gqlRanges(),
        [
          Range(start: startsFromWithoutArtifact, end: 1599),
          Range(start: 1701, end: 2000),
        ],
      );
      expect(snapshotQueryMins, [startsFromWithoutArtifact]);
      expect(await fileIds(), contains(inSnapshot.fileId));
    });

    test('leaves no block between the look-back and the tip uncovered',
        () async {
      await sync();

      final overlaps = overlapsWithNoGaps(
        [Range(start: 1600, end: 1700), ...gqlRanges()],
        from: startsFromWithoutArtifact,
        to: currentBlockHeight,
      );
      expect(overlaps, isEmpty);
    });
  });
}
