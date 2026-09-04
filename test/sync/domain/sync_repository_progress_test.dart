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

/// The progress number a sync reports, driven through the real repository.
///
/// The bar used to give the drive walk 0.0-0.9 and then jump: 0.92 for ghost
/// folders, 0.96 for transaction statuses, 1.0 for done. Two phases of unknown
/// length - one of them a gateway round trip - passed with the bar perfectly
/// still, which reads as hung.
///
/// These are the guarantees that replaced it, and they are asserted off a real
/// `SyncRepository` over a real in-memory database with only the gateway
/// mocked. A test that builds a `SyncProgress` by hand cannot catch a wrong
/// number in the repository; that gap is how a fake count shipped once already.
///
/// Two rules run through them. Bar travel belongs to phases that can report
/// what they have done, so the phase assertions look for distinct values
/// strictly inside a phase's open interval - a count over the whole tail is
/// satisfied by the fixed boundaries alone and guards nothing. And a phase
/// that cannot report does not get a number at all: it says so, and the tests
/// check both that it says so and that it stops.
void main() {
  // The contract, restated here rather than imported: these tests are supposed
  // to fail if the implementation's constants move.
  const driveWalkEnd = 0.85;
  const ghostFoldersEnd = 0.88;
  const pendingScanEnd = 0.92;
  const txPrepEnd = 0.97;
  const txStatusEnd = 0.99;

  const tailMessages = {
    'Creating ghost folders...',
    'Updating transaction statuses...',
    // The timeout handler's message. Without it here, a sync whose gateway
    // call timed out would have its tail emissions counted as pre-tail and
    // fail the walk-share assertion for a reason that has nothing to do with
    // the walk.
    'Completing sync...',
    'Sync complete',
  };

  const driveId = 'drive-id';
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

  FolderEntity folder(String id, {String? parentFolderId}) => FolderEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: id,
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = ownerAddress
        ..createdAt = DateTime(2026, 8, 29);

  FileEntity file(String id, {String parentFolderId = rootFolderId}) =>
      FileEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: id,
        size: 1024,
        lastModifiedDate: DateTime(2026, 8, 29),
        dataTxId: 'data-$id',
        dataContentType: 'text/plain',
      )
        ..txId = 'metadata-$id'
        ..ownerAddress = ownerAddress
        ..createdAt = DateTime(2026, 8, 29);

  /// What the gateway returns for this drive: one transaction per entity at
  /// [blockHeights] (ascending by default), and those entities when the sync
  /// asks what the transactions were.
  void gatewayReturns(List<Entity> entities, {List<int>? blockHeights}) {
    final heights =
        blockHeights ?? [for (var i = 0; i < entities.length; i++) 10 + i];

    when(() => arweave.getSegmentedTransactionsFromDrive(
              any(),
              ownerAddress: any(named: 'ownerAddress'),
              minBlockHeight: any(named: 'minBlockHeight'),
              maxBlockHeight: any(named: 'maxBlockHeight'),
              strategy: any(named: 'strategy'),
            ))
        .thenAnswer(
            (_) => Stream.value([for (final h in heights) transactionAt(h)]));

    when(() => arweave.createDriveEntityHistoryFromTransactions(
          any(),
          any(),
          any(),
          driveId: any(named: 'driveId'),
          ownerAddress: any(named: 'ownerAddress'),
          currentBlockHeight: any(named: 'currentBlockHeight'),
        )).thenAnswer((_) async {
      final block = BlockEntities(10)..entities = [...entities];
      return DriveEntityHistory(10, [block]);
    });
  }

  Future<void> insertDrive({int? lastBlockHeight}) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: 'Test Drive',
            ownerAddress: ownerAddress,
            rootFolderId: rootFolderId,
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: Value(lastBlockHeight),
          ),
        );
  }

  Future<List<SyncProgress>> collectSingleDrive(
      {bool withWallet = false}) async {
    final emitted = <SyncProgress>[];
    await for (final progress in syncRepository.syncSingleDrive(
      driveId: driveId,
      wallet: withWallet ? wallet : null,
    )) {
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

  /// Every consecutive pair, so a decrease anywhere in the run is named with
  /// the pair that caused it.
  void expectMonotonic(List<SyncProgress> emitted) {
    expect(emitted, isNotEmpty);
    for (var i = 1; i < emitted.length; i++) {
      expect(
        emitted[i].progress,
        greaterThanOrEqualTo(emitted[i - 1].progress),
        reason: 'emission $i (${emitted[i].progress}) went backwards from '
            'emission ${i - 1} (${emitted[i - 1].progress})',
      );
    }
  }

  /// The distinct values reported strictly inside one phase's own share of
  /// the bar - its open interval, so neither boundary counts.
  ///
  /// Counting the whole stretch from the walk to 1.0 does not work as a guard:
  /// the fixed phase boundaries alone put three values in it, so a test on
  /// that range stays green with every intra-phase report deleted. Only
  /// reporting from inside a phase can put a value strictly between that
  /// phase's own two ends.
  List<double> insidePhase(
    List<SyncProgress> emitted,
    double start,
    double end,
  ) =>
      (emitted
          .map((p) => p.progress)
          .where((v) => v > start && v < end)
          .toSet()
          .toList()
        ..sort());

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
          activeDriveIds: {driveId},
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

    gatewayReturns([]);

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

  group('all drives', () {
    setUp(() async {
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns([folder(rootFolderId), file('file-a'), file('file-b')]);
    });

    test('progress never goes backwards', () async {
      expectMonotonic(await collectAllDrives());
    });

    test('a successful sync ends on exactly 1.0', () async {
      final emitted = await collectAllDrives();

      expect(emitted.last.progress, 1.0);
      expect(emitted.last.statusMessage, 'Sync complete');
      // Not 0.999, and not a value that only rounds to 100%.
      expect(emitted.last.progress == 1.0, isTrue);
    });

    test('the drive walk stays inside its share of the bar', () async {
      final emitted = await collectAllDrives();

      final beforeTheTail =
          emitted.where((p) => !tailMessages.contains(p.statusMessage));

      expect(beforeTheTail, isNotEmpty);
      for (final progress in beforeTheTail) {
        expect(progress.progress, lessThanOrEqualTo(driveWalkEnd),
            reason: 'the walk took more than its share');
      }
    });

    test('each tail phase stays inside its own share', () async {
      final emitted = await collectAllDrives();

      for (final progress in emitted) {
        switch (progress.statusMessage) {
          case 'Creating ghost folders...':
            expect(progress.progress,
                inInclusiveRange(driveWalkEnd, ghostFoldersEnd));
            break;
          case 'Updating transaction statuses...':
            expect(progress.progress,
                inInclusiveRange(ghostFoldersEnd, txStatusEnd));
            break;
          case 'Sync complete':
            expect(progress.progress, 1.0);
            break;
        }
      }
    });

    test('the transaction-status phase advances off its own local reads',
        () async {
      // The three database reads that run before the gateway is touched -
      // owner overrides, per-drive owners, pending rows - each report a step.
      // Strictly inside the phase, so only reporting from inside it can
      // satisfy this: the phase's own boundaries sit on the excluded ends.
      final inside =
          insidePhase(await collectAllDrives(), pendingScanEnd, txPrepEnd);

      expect(inside.length, greaterThanOrEqualTo(2),
          reason: 'the phase reported $inside');
      for (var i = 1; i < inside.length; i++) {
        expect(inside[i], greaterThan(inside[i - 1]));
      }
    });
  });

  group('single drive', () {
    setUp(() async {
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns([folder(rootFolderId), file('file-a'), file('file-b')]);
    });

    test('progress never goes backwards', () async {
      expectMonotonic(await collectSingleDrive());
    });

    test('a successful sync ends on exactly 1.0', () async {
      final emitted = await collectSingleDrive();

      expect(emitted.last.progress, 1.0);
      expect(emitted.last.statusMessage, 'Sync complete');
    });

    test('the drive walk stays inside its share of the bar', () async {
      final emitted = await collectSingleDrive();

      final beforeTheTail =
          emitted.where((p) => !tailMessages.contains(p.statusMessage));

      expect(beforeTheTail, isNotEmpty);
      for (final progress in beforeTheTail) {
        expect(progress.progress, lessThanOrEqualTo(driveWalkEnd));
      }
    });

    test('each tail phase stays inside its own share', () async {
      final emitted = await collectSingleDrive();

      for (final progress in emitted) {
        switch (progress.statusMessage) {
          case 'Creating ghost folders...':
            expect(progress.progress,
                inInclusiveRange(driveWalkEnd, ghostFoldersEnd));
            break;
          case 'Updating transaction statuses...':
            expect(progress.progress,
                inInclusiveRange(ghostFoldersEnd, txStatusEnd));
            break;
          case 'Sync complete':
            expect(progress.progress, 1.0);
            break;
        }
      }
    });

    test('the pending-scan phase advances off its own local reads', () async {
      // The drive's revisions, the snapshot-covered transaction ids, and the
      // hidden-item preference: three reads that were already being made,
      // reported as each lands. Strictly inside the phase, so the phase's own
      // boundaries cannot satisfy it.
      final inside = insidePhase(
          await collectSingleDrive(), ghostFoldersEnd, pendingScanEnd);

      expect(inside.length, greaterThanOrEqualTo(2),
          reason: 'the phase reported $inside');
      for (var i = 1; i < inside.length; i++) {
        expect(inside[i], greaterThan(inside[i - 1]));
      }
    });

    test(
        'the gateway phase says it cannot be measured, and then stops saying it',
        () async {
      // Same guarantee as the all-drives path, through a different callee:
      // the single-drive sync sets and clears the flag in
      // _updateTransactionStatusesForDrive, with its own call sites. The
      // group's setUp already inserted the drive.
      await db.into(db.networkTransactions).insert(
            NetworkTransactionsCompanion.insert(id: 'pending-tx'),
          );

      // The confirmation loop is only reached with a wallet.
      final emitted = await collectSingleDrive(withWallet: true);

      final indeterminate = emitted.where((p) => p.isIndeterminate).toList();
      expect(indeterminate, isNotEmpty,
          reason: 'the gateway phase pretended to have a number');
      for (final progress in indeterminate) {
        expect(progress.statusMessage, 'Updating transaction statuses...');
      }
      expect(emitted.last.isIndeterminate, isFalse);
      expect(emitted.last.progress, 1.0);
    });
  });

  group('the arithmetic behind the bar', () {
    test('block heights that arrive out of order cannot push the bar back',
        () async {
      // A drive's own progress is 1 - (head - blockHeight) / range, so a
      // history that hands back a lower block than the one before it computes
      // a smaller - here negative - number. Composite histories can do exactly
      // that. Nothing downstream may see the bar move backwards because of it.
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns(
        [folder(rootFolderId), file('file-a'), file('file-b')],
        blockHeights: [95, 85, 75],
      );

      final emitted = await collectSingleDrive();

      expectMonotonic(emitted);
      for (final progress in emitted) {
        expect(progress.progress, greaterThanOrEqualTo(0.0),
            reason: 'a negative progress reached the bar');
      }
      expect(emitted.last.progress, 1.0);
    });

    test('all drives: out-of-order block heights cannot push the bar back',
        () async {
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns(
        [folder(rootFolderId), file('file-a'), file('file-b')],
        blockHeights: [95, 85, 75],
      );

      final emitted = await collectAllDrives();

      expectMonotonic(emitted);
      for (final progress in emitted) {
        expect(progress.progress, greaterThanOrEqualTo(0.0));
      }
      expect(emitted.last.progress, 1.0);
    });

    test('ghost folder creation moves the bar as it writes the rows', () async {
      // Three files whose parent folders were never found: three ghost rows,
      // written one at a time inside the phase that used to be a single jump.
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns([
        folder(rootFolderId),
        file('file-a', parentFolderId: 'ghost-one'),
        file('file-b', parentFolderId: 'ghost-two'),
        file('file-c', parentFolderId: 'ghost-three'),
      ]);

      final emitted = await collectSingleDrive(withWallet: true);

      expect(await db.select(db.folderEntries).get(),
          hasLength(greaterThanOrEqualTo(3)));

      final duringGhosts = emitted
          .where(
              (p) => p.progress > driveWalkEnd && p.progress < ghostFoldersEnd)
          .map((p) => p.progress)
          .toSet();

      expect(duringGhosts, hasLength(greaterThanOrEqualTo(2)),
          reason: 'ghost creation reported $duringGhosts');
      expectMonotonic(emitted);
    });

    test('a transaction mined above the head block cannot break the bar',
        () async {
      // The head block height is read once, at the top of a sync that then
      // runs for minutes. A transaction mined after that read sits above it,
      // and the walk's own number - 1 - (head - height) / range - goes above
      // 1: head 100 with transactions at 99, 101 and 103 computes 1.6 and 3.2.
      // Unbounded, the first of those became the high-water mark and every
      // later emission, "Sync complete" included, was pinned to it: a bar
      // reading 240% that never moved again.
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns(
        [folder(rootFolderId), file('file-a'), file('file-b')],
        blockHeights: [99, 101, 103],
      );

      final emitted = await collectSingleDrive();

      for (final progress in emitted) {
        expect(progress.progress, inInclusiveRange(0.0, 1.0),
            reason: 'a progress outside 0..1 reached the bar');
      }
      for (final progress
          in emitted.where((p) => !tailMessages.contains(p.statusMessage))) {
        expect(progress.progress, lessThanOrEqualTo(driveWalkEnd),
            reason: 'the overshoot leaked out of the walk');
      }
      // The tail is not pinned behind the overshoot: each phase still closes
      // on its own boundary, exactly.
      expect(emitted.map((p) => p.progress), contains(ghostFoldersEnd));
      expect(emitted.last.progress, 1.0);
      expect(emitted.last.statusMessage, 'Sync complete');
      expectMonotonic(emitted);
    });

    test('all drives: a transaction above the head cannot break the bar',
        () async {
      // The same overshoot, through the other path: here the walk's value is
      // divided across the drives in the sync before it is scaled, and the cap
      // has to be applied at that site too.
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns(
        [folder(rootFolderId), file('file-a'), file('file-b')],
        blockHeights: [99, 101, 103],
      );

      final emitted = await collectAllDrives();

      for (final progress in emitted) {
        expect(progress.progress, inInclusiveRange(0.0, 1.0));
      }
      for (final progress
          in emitted.where((p) => !tailMessages.contains(p.statusMessage))) {
        expect(progress.progress, lessThanOrEqualTo(driveWalkEnd),
            reason: 'the overshoot leaked out of the walk');
      }
      expect(emitted.map((p) => p.progress), contains(ghostFoldersEnd));
      expect(emitted.last.progress, 1.0);
      expectMonotonic(emitted);
    });

    test('a walk value over its phase end cannot pin the tail behind it',
        () async {
      // The overshoot does not have to reach 1.0 to do damage. First block 90
      // against a head of 100 makes the range 10, so a transaction at 103
      // computes 1.3, and the walk hands up 1.3 * its share = 0.884 - inside
      // 0..1, and past the end of the walk's own phase. Left uncapped that
      // becomes the high-water mark and swallows the ghost phase whole.
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns(
        [folder(rootFolderId), file('file-a'), file('file-b')],
        blockHeights: [90, 95, 103],
      );

      final emitted = await collectSingleDrive();

      for (final progress
          in emitted.where((p) => !tailMessages.contains(p.statusMessage))) {
        expect(progress.progress, lessThanOrEqualTo(driveWalkEnd),
            reason: 'the walk reported ${progress.progress}, past its share');
      }
      expect(emitted.map((p) => p.progress), contains(ghostFoldersEnd),
          reason: 'the ghost phase closed above its own boundary');
      expect(emitted.last.progress, 1.0);
      expectMonotonic(emitted);
    });

    test(
        'the gateway phase says it cannot be measured, and then stops saying it',
        () async {
      // A pending transaction gives the confirmation loop a batch to run, and
      // the loop is the one stretch of a sync nothing here can measure. The
      // bar is told so rather than handed a number to sit on.
      await insertDrive(lastBlockHeight: 50);
      gatewayReturns([folder(rootFolderId), file('file-a')]);
      await db.into(db.networkTransactions).insert(
            NetworkTransactionsCompanion.insert(id: 'pending-tx'),
          );

      final emitted = await collectAllDrives();

      final indeterminate = emitted.where((p) => p.isIndeterminate).toList();
      expect(indeterminate, isNotEmpty,
          reason: 'the gateway phase pretended to have a number');
      for (final progress in indeterminate) {
        // It says which phase it is in while it says it cannot measure it -
        // an animated bar with no words is worse than a still one.
        expect(progress.statusMessage, 'Updating transaction statuses...');
      }
      // And it is over by the time the sync is.
      expect(emitted.last.isIndeterminate, isFalse);
      expect(emitted.last.progress, 1.0);
    });
  });

  group('the sink every emission passes through', () {
    SyncProgress at(double progress) => SyncProgress(
          numberOfEntities: 0,
          progress: progress,
          entitiesSynced: 0,
          drivesCount: 1,
          drivesSynced: 0,
          numberOfDrivesAtGetMetadataPhase: 0,
        );

    test('a progress above 1.0 never becomes the high-water mark', () {
      final sink = MonotonicProgressSink();

      // What the walk hands up when a transaction is newer than the head.
      expect(sink.raise(at(2.4)).progress, 1.0);
      // And the mark it left behind is 1.0, not 2.4 - so the next emission is
      // a bar at 100%, not a bar at 240%.
      expect(sink.raise(at(0.5)).progress, 1.0);
    });

    test('work still running when the stream closes is not aborted by it',
        () async {
      // `Future.timeout` does not cancel its source: after the transaction
      // status update times out, the abandoned loop goes on issuing its
      // remaining confirmation batches while the sync finishes and closes this
      // sink. Reporting from that loop must not throw, or the batches it had
      // left are silently dropped and those uploads stay "pending" for another
      // whole cycle.
      final sink = MonotonicProgressSink();
      final seen = <double>[];
      final subscription = sink.stream.listen((p) => seen.add(p.progress));

      sink.add(at(0.9));
      await Future.delayed(Duration.zero);
      await sink.close();

      var batchesIssued = 0;
      for (var batch = 0; batch < 4; batch++) {
        batchesIssued++;
        sink.add(at(0.95));
      }
      sink.addError(StateError('a late failure nobody is listening for'));

      expect(batchesIssued, 4,
          reason: 'reporting after the close aborted the remaining batches');
      expect(seen, [0.9]);
      await subscription.cancel();
    });
  });
}
