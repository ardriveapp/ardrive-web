import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockARNSRepository extends Mock implements ARNSRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockWallet extends Mock implements Wallet {}

/// What the sync reports while it is fetching entity metadata.
///
/// This is the slowest stretch of a sync and it used to be the one nothing
/// reported: every revision's metadata body is its own HTTP round trip, run
/// `maxConcurrentDataFetches` at a time, and the only number the repository
/// published during it - `entitiesSynced` - moves when revisions are
/// *inserted*, which is after a whole batch's fetches are already done. A
/// drive with thousands of revisions therefore held one unchanging line for
/// minutes.
///
/// Driven through the real `SyncRepository` over a real in-memory database
/// with only the gateway mocked, and the gateway's stub calls the hook the
/// repository handed it - once per entity, as the real fetch loop does. A test
/// that assembled `SyncProgress` by hand could not tell a live count from a
/// dead one.
void main() {
  const driveId = 'drive-id';
  const otherDriveId = 'other-drive-id';
  const rootFolderId = 'root-folder-id';
  const ownerAddress = 'owner-address';

  late Database db;
  late MockArweaveService arweave;
  late MockConfigService configService;
  late _MockSnapshotValidationService snapshotValidation;
  late _MockARNSRepository arnsRepository;
  late _MockUserPreferencesRepository userPreferences;
  late _MockWallet wallet;
  late SyncRepository syncRepository;

  DriveEntityHistoryTransactionModel transactionAt(int height) {
    return DriveEntityHistoryTransactionModel(
      transactionCommonMixin:
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              .fromJson({
        'id': 'tx-$height',
        'owner': {'address': ownerAddress},
        'tags': <dynamic>[],
        'block': {'height': height, 'timestamp': height * 100},
      }),
      cursor: 'cursor-$height',
    );
  }

  FolderEntity folder(String id, String drive, {String? parentFolderId}) =>
      FolderEntity(
        id: id,
        driveId: drive,
        parentFolderId: parentFolderId,
        name: id,
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = ownerAddress
        ..createdAt = DateTime(2026, 8, 29);

  FileEntity file(String id, String drive, {String? parentFolderId}) =>
      FileEntity(
        id: id,
        driveId: drive,
        parentFolderId: parentFolderId ?? '$drive-root',
        name: id,
        size: 1024,
        lastModifiedDate: DateTime(2026, 8, 29),
        dataTxId: 'data-$id',
        dataContentType: 'text/plain',
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = ownerAddress
        ..createdAt = DateTime(2026, 8, 29);

  /// The gateway, drive by drive: one transaction per entity, and - when the
  /// sync asks what those transactions were - the entities, reported one at a
  /// time through the hook the repository passed in.
  ///
  /// The per-entity call is the whole point. A stub that answered the batch in
  /// one go would leave the repository with nothing to publish until the batch
  /// was over, which is precisely the behaviour these tests exist to reject.
  void gatewayReturns(Map<String, List<Entity>> entitiesByDrive) {
    for (final entry in entitiesByDrive.entries) {
      when(() => arweave.getSegmentedTransactionsFromDrive(
            entry.key,
            ownerAddress: any(named: 'ownerAddress'),
            minBlockHeight: any(named: 'minBlockHeight'),
            maxBlockHeight: any(named: 'maxBlockHeight'),
            strategy: any(named: 'strategy'),
          )).thenAnswer((_) => Stream.value([
            for (var i = 0; i < entry.value.length; i++) transactionAt(10 + i),
          ]));
    }

    when(() => arweave.createDriveEntityHistoryFromTransactions(
          any(),
          any(),
          any(),
          driveId: any(named: 'driveId'),
          ownerAddress: any(named: 'ownerAddress'),
          currentBlockHeight: any(named: 'currentBlockHeight'),
          onEntityFetched: any(named: 'onEntityFetched'),
        )).thenAnswer((invocation) async {
      final items = invocation.positionalArguments.first
          as List<DriveEntityHistoryTransactionModel>;
      final onEntityFetched =
          invocation.namedArguments[#onEntityFetched] as void Function()?;
      final drive = invocation.namedArguments[#driveId] as String;

      for (var i = 0; i < items.length; i++) {
        // A round trip apiece, exactly as the real loop has.
        await Future<void>.delayed(Duration.zero);
        onEntityFetched?.call();
      }

      final block = BlockEntities(10)..entities = [...?entitiesByDrive[drive]];
      return DriveEntityHistory(10, [block]);
    });
  }

  Future<void> insertDrive(String id, {int? lastBlockHeight}) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: id,
            name: 'Drive $id',
            ownerAddress: ownerAddress,
            rootFolderId: '$id-root',
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: Value(lastBlockHeight),
          ),
        );
  }

  Future<List<SyncProgress>> collectSingleDrive() async {
    final emitted = <SyncProgress>[];
    await for (final progress
        in syncRepository.syncSingleDrive(driveId: driveId)) {
      emitted.add(progress);
    }
    await Future.delayed(const Duration(milliseconds: 20));
    return emitted;
  }

  Future<List<SyncProgress>> collectAllDrives() async {
    final emitted = <SyncProgress>[];
    await for (final progress in syncRepository.syncAllDrives(wallet: wallet)) {
      emitted.add(progress);
    }
    await Future.delayed(const Duration(milliseconds: 20));
    return emitted;
  }

  /// Every `(completed, total)` the run reported while it had a fetch to
  /// report, with consecutive repeats collapsed - other phases republish the
  /// pair unchanged as they emit, and a repeat is not a report.
  List<List<int>> fetchReports(List<SyncProgress> emitted) {
    final reports = <List<int>>[];
    for (final p in emitted.where((p) => p.metadataFetchesTotal > 0)) {
      final pair = [p.metadataFetchesCompleted, p.metadataFetchesTotal];
      if (reports.isEmpty ||
          reports.last[0] != pair[0] ||
          reports.last[1] != pair[1]) {
        reports.add(pair);
      }
    }
    return reports;
  }

  setUp(() {
    db = getTestDb();
    arweave = MockArweaveService();
    configService = MockConfigService();
    snapshotValidation = _MockSnapshotValidationService();
    arnsRepository = _MockARNSRepository();
    userPreferences = _MockUserPreferencesRepository();
    wallet = _MockWallet();

    when(() => wallet.getAddress()).thenAnswer((_) async => ownerAddress);

    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
      autoSync: true,
    ));

    when(() => arweave.getCurrentBlockHeight()).thenAnswer((_) async => 100);
    when(() => arweave.clearUserDriveTxsCache()).thenReturn(null);
    when(() => arweave.snapshotMetadataHits).thenReturn(<String, int>{});
    when(() => arweave.snapshotMetadataMisses).thenReturn(<String, int>{});
    when(() => arweave.probeActiveDriveIds(
          driveIds: any(named: 'driveIds'),
          minBlockHeight: any(named: 'minBlockHeight'),
          ownerAddress: any(named: 'ownerAddress'),
        )).thenAnswer((_) async => (
          activeDriveIds: {driveId, otherDriveId},
          isComplete: true,
        ));
    when(() => arweave.getTransactionConfirmations(
          any(),
          owner: any(named: 'owner'),
          ownersByTxId: any(named: 'ownersByTxId'),
          ownerOverrides: any(named: 'ownerOverrides'),
          verifiedSink: any(named: 'verifiedSink'),
        )).thenAnswer((_) async => <String?, int>{});
    when(() => arnsRepository.getAntRecordsForWallet(any(),
        update: any(named: 'update'))).thenAnswer((_) async => <ANTRecord>[]);
    when(() => arnsRepository.waitForARNSRecordsToUpdate())
        .thenAnswer((_) async {});
    when(() => arnsRepository.saveAllFilesWithAssignedNames())
        .thenAnswer((_) async {});
    when(() => userPreferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
      ),
    );
    when(() => userPreferences.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});

    gatewayReturns({driveId: [], otherDriveId: []});

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: BatchProcessor(),
      snapshotValidationService: snapshotValidation,
      arnsRepository: arnsRepository,
      userPreferencesRepository: userPreferences,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('a single drive', () {
    setUp(() async {
      await insertDrive(driveId, lastBlockHeight: 50);
      gatewayReturns({
        driveId: [
          folder(rootFolderId, driveId),
          file('file-a', driveId),
          file('file-b', driveId),
          file('file-c', driveId),
        ],
      });
    });

    test('reports every completed fetch, one at a time, against a real total',
        () async {
      final reports = fetchReports(await collectSingleDrive());

      // The total is announced with the batch, before any of it has come
      // back, and then the count climbs through it one fetch at a time. This
      // is the whole difference between "Reading 3 of 4..." and a line that
      // only changes when the batch is over.
      expect(reports, [
        [0, 4],
        [1, 4],
        [2, 4],
        [3, 4],
        [4, 4],
      ]);
    });

    test('the count never goes backwards and never passes its total', () async {
      final reports = fetchReports(await collectSingleDrive());

      expect(reports, isNotEmpty, reason: 'nothing was reported at all');
      for (var i = 0; i < reports.length; i++) {
        expect(reports[i][0], lessThanOrEqualTo(reports[i][1]));
        if (i > 0) {
          expect(reports[i][0], greaterThanOrEqualTo(reports[i - 1][0]));
          expect(reports[i][1], greaterThanOrEqualTo(reports[i - 1][1]));
        }
      }
    });

    test(
        'is given back when the walk ends, so later phases speak for '
        'themselves', () async {
      final emitted = await collectSingleDrive();

      // Left set, "Reading 4 of 4..." would sit on top of ghost folders,
      // transaction statuses and "Sync complete" - every one of which has
      // something of its own to say.
      expect(emitted.last.metadataFetchesTotal, 0);
      expect(emitted.last.metadataFetchesCompleted, 0);
      expect(emitted.last.statusMessage, 'Sync complete');
    });

    test('a drive with nothing to fetch reports no fetch', () async {
      // No total is ever invented: a phase with nothing of this kind to say
      // says nothing, and the surfaces fall back to what they said before.
      gatewayReturns({driveId: []});

      final emitted = await collectSingleDrive();

      expect(emitted.every((p) => p.metadataFetchesTotal == 0), isTrue);
    });
  });

  group('all drives', () {
    setUp(() async {
      await insertDrive(driveId, lastBlockHeight: 50);
      await insertDrive(otherDriveId, lastBlockHeight: 50);
      gatewayReturns({
        driveId: [
          folder(rootFolderId, driveId),
          file('file-a', driveId),
        ],
        otherDriveId: [
          folder('$otherDriveId-root', otherDriveId),
          file('file-b', otherDriveId),
          file('file-c', otherDriveId),
        ],
      });
    });

    test('one tally across drives that are fetching at the same time',
        () async {
      // The drives run concurrently over one sink. A per-drive figure would
      // be several numbers taking turns in one line, each dropping when
      // another drive got a word in - so the tally is the sync's, and both
      // halves of it only climb.
      final reports = fetchReports(await collectAllDrives());

      expect(reports, isNotEmpty, reason: 'nothing was reported at all');
      for (var i = 1; i < reports.length; i++) {
        expect(
          reports[i][0],
          greaterThanOrEqualTo(reports[i - 1][0]),
          reason: 'completed went backwards at report $i: $reports',
        );
        expect(
          reports[i][1],
          greaterThanOrEqualTo(reports[i - 1][1]),
          reason: 'the total went backwards at report $i: $reports',
        );
      }

      // Five entities across the two drives, every one of them fetched and
      // every one of them reported.
      expect(reports.last, [5, 5]);
    });

    test('is given back when the walk ends', () async {
      final emitted = await collectAllDrives();

      expect(emitted.last.metadataFetchesTotal, 0);
      expect(emitted.last.metadataFetchesCompleted, 0);
    });
  });
}
