import 'dart:async';

import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockSnapshotValidationService extends Mock
    implements SnapshotValidationService {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockWallet extends Mock implements Wallet {}

/// A gateway that is slow to say which pending transactions were mined, as it
/// is after a big first sync.
///
/// The sync's status pass is given a fixed time. When it runs out the sync
/// still finishes on time, the pass is stopped (not left running beside
/// whatever finishes the job), the sync says the pass was cut short, and a
/// later refresh settles the rest. Real repository, real in-memory database;
/// only the gateway is a fake.
void main() {
  const driveId = 'drive-id';
  const ownerAddress = 'owner-address';
  const pendingTxId = 'pending-data-tx';

  late Database db;
  late MockArweaveService arweave;
  late SyncRepository syncRepository;
  late _MockWallet wallet;
  late MockConfigService configService;
  late _MockUserPreferencesRepository userPreferences;

  /// How many confirmation queries were asked, and the slow answer to hold.
  late int asked;
  late Completer<Map<String?, int>> slowAnswer;

  Future<NetworkTransaction> pendingRow() => (db.select(db.networkTransactions)
        ..where((t) => t.id.equals(pendingTxId)))
      .getSingle();

  setUp(() async {
    db = getTestDb();
    arweave = MockArweaveService();
    wallet = _MockWallet();
    asked = 0;
    slowAnswer = Completer<Map<String?, int>>();
    configService = MockConfigService();
    userPreferences = _MockUserPreferencesRepository();

    when(() => wallet.getAddress()).thenAnswer((_) async => ownerAddress);
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableSyncFromSnapshot: false,
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
    when(() => arweave.getSegmentedTransactionsFromDrive(
          any(),
          ownerAddress: any(named: 'ownerAddress'),
          minBlockHeight: any(named: 'minBlockHeight'),
          maxBlockHeight: any(named: 'maxBlockHeight'),
          strategy: any(named: 'strategy'),
        )).thenAnswer((_) => const Stream.empty());
    when(() => arweave.getTransactionConfirmations(
          any(),
          owner: any(named: 'owner'),
          ownersByTxId: any(named: 'ownersByTxId'),
          ownerOverrides: any(named: 'ownerOverrides'),
          verifiedSink: any(named: 'verifiedSink'),
        )).thenAnswer((_) {
      asked++;
      return slowAnswer.future;
    });
    when(() => userPreferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
      ),
    );
    when(() => userPreferences.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});

    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: driveId,
            name: 'Test Drive',
            ownerAddress: ownerAddress,
            rootFolderId: 'root-folder-id',
            privacy: DrivePrivacyTag.public,
            lastBlockHeight: const Value(50),
          ),
        );
    await db.driveDao.insertNewNetworkTransactions([
      NetworkTransactionsCompanion(
        id: const Value(pendingTxId),
        status: const Value(TransactionStatus.pending),
        dateCreated: Value(DateTime.now()),
      ),
    ]);

    syncRepository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: BatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      userPreferencesRepository: userPreferences,
      statusUpdateTimeout: const Duration(milliseconds: 100),
    );
  });

  tearDown(() => db.close());

  Future<List<SyncProgress>> syncAll() => syncRepository
      .syncAllDrives(wallet: wallet)
      .toList()
      .timeout(const Duration(seconds: 5));

  test('the sync completes on time while the gateway is still slow', () async {
    final emitted = await syncAll();

    expect(emitted.last.statusMessage, 'Sync complete');
    expect(emitted.last.progress, 1.0);
    expect(slowAnswer.isCompleted, isFalse,
        reason: 'the sync must not have waited for the gateway');
  });

  test('it says the status pass was cut short', () async {
    final emitted = await syncAll();

    expect(emitted.last.statusPassTimedOut, isTrue);
  });

  // A batch that runs out of time keeps what it had and moves on, so the
  // pass finishes in time with that batch's rest still pending: owed all the
  // same, so the follow-up must be asked for.
  test('a batch that ran out of time asks for the follow-up too', () async {
    final repository = SyncRepository(
      arweave: arweave,
      driveDao: db.driveDao,
      configService: configService,
      batchProcessor: BatchProcessor(),
      snapshotValidationService: _MockSnapshotValidationService(),
      userPreferencesRepository: userPreferences,
      statusUpdateTimeout: const Duration(seconds: 5),
      statusBatchTimeout: const Duration(milliseconds: 50),
    );

    final emitted = await repository
        .syncAllDrives(wallet: wallet)
        .toList()
        .timeout(const Duration(seconds: 4));

    expect(emitted.last.statusMessage, 'Sync complete');
    expect(emitted.last.statusPassTimedOut, isTrue);
    expect((await pendingRow()).status, TransactionStatus.pending);
  });

  test('a pass that finishes in time says nothing', () async {
    slowAnswer.complete({pendingTxId: kRequiredTxConfirmationCount});

    final emitted = await syncAll();

    expect(emitted.last.statusPassTimedOut, isFalse);
    expect((await pendingRow()).status, TransactionStatus.confirmed);
  });

  test('the abandoned pass is stopped and writes nothing after the timeout',
      () async {
    await syncAll();
    expect(asked, 1);

    // The gateway finally answers the query the stopped pass was waiting on.
    slowAnswer.complete({pendingTxId: kRequiredTxConfirmationCount});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect((await pendingRow()).status, TransactionStatus.pending,
        reason: 'only the follow-up may write; two passes must not overlap');
  });

  test('the follow-up refresh then confirms what the sync left pending',
      () async {
    await syncAll();
    slowAnswer.complete({pendingTxId: kRequiredTxConfirmationCount});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    await syncRepository.refreshTransactionStatuses(
      ownerAddress: ownerAddress,
      cancellationToken: SyncCancellationToken(),
    );

    expect((await pendingRow()).status, TransactionStatus.confirmed);
    expect(await db.driveDao.hasPendingTransactions(), isFalse);
  });

  test('stopping the sync stops the status pass as well', () async {
    final token = SyncCancellationToken();
    final errors = <Object>[];
    final done = Completer<void>();
    syncRepository
        .syncAllDrives(wallet: wallet, cancellationToken: token)
        .listen((_) {}, onError: errors.add, onDone: done.complete);

    // The pass is waiting on the gateway; the stop arrives before the timeout.
    while (asked == 0) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    token.cancel();
    await done.future.timeout(const Duration(seconds: 5));

    slowAnswer.complete({pendingTxId: kRequiredTxConfirmationCount});
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect((await pendingRow()).status, TransactionStatus.pending);
  });

  group('a status pass token', () {
    test('follows a sync cancelled later', () async {
      final sync = SyncCancellationToken();
      final pass = statusPassTokenFor(sync);
      addTearDown(pass.dispose);

      sync.cancel();
      await Future<void>.delayed(Duration.zero);

      expect(pass.token.isCancelled, isTrue);
    });

    // The cancel stream is broadcast, so a sync stopped before the pass
    // began sent its event to nobody and the pass ran on.
    test('starts cancelled for a sync already cancelled', () {
      final sync = SyncCancellationToken()..cancel();
      final pass = statusPassTokenFor(sync);
      addTearDown(pass.dispose);

      expect(pass.token.isCancelled, isTrue);
    });
  });
}
