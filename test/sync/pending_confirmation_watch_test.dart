import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/sync/domain/sync_run.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class MockSyncRepository extends Mock implements SyncRepository {}

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class MockActivityTracker extends Mock implements ActivityTracker {}

class _FakeWallet extends Fake implements Wallet {}

class _FakeSecretKey extends Fake implements SecretKey {}

class _FakeSyncRun extends Fake implements SyncRun {}

/// Logging in should not walk every drive's whole history unasked - but it
/// must still notice new drives, and it must still finish the job when an
/// upload is left unresolved. These drive the real [SyncCubit]; only the
/// repository underneath it is a mock.

/// Confirming an upload, without turning the app into a polling client.
///
/// An upload writes its file locally and shows it at once, and nothing
/// afterwards ever confirmed it. `autoSync` ships false in all three flavours,
/// so the periodic sync it gates never runs - the comment promising that
/// "background periodic sync will update lastBlockHeight naturally" described
/// a timer nothing starts. A file therefore sat unconfirmed until the reader
/// pressed sync or logged in again.
///
/// The rule this must not break while fixing that: with nothing pending, the
/// app stays exactly as quiet as it is now. This is a pending check that
/// syncs, not a periodic sync with a pending check bolted on - which is the
/// whole difference between it and the `autoSync` flag that is off precisely
/// because it is unconditional.
void main() {
  late MockProfileCubit profileCubit;
  late MockActivityCubit activityCubit;
  late MockPromptToSnapshotBloc promptToSnapshotBloc;
  late MockTabVisibilitySingleton tabVisibility;
  late MockConfigService configService;
  late MockConfig config;
  late MockActivityTracker activityTracker;
  late MockSyncRepository syncRepository;
  late MockUserPreferencesRepository userPreferencesRepository;

  setUpAll(() {
    registerFallbackValue(false);
    registerFallbackValue(_FakeWallet());
    registerFallbackValue(_FakeSecretKey());
    registerFallbackValue(_FakeSyncRun());
  });

  setUp(() {
    profileCubit = MockProfileCubit();
    activityCubit = MockActivityCubit();
    promptToSnapshotBloc = MockPromptToSnapshotBloc();
    tabVisibility = MockTabVisibilitySingleton();
    configService = MockConfigService();
    config = MockConfig();
    activityTracker = MockActivityTracker();
    syncRepository = MockSyncRepository();
    // The returning-reader probe fires on the same "nothing owed" branch these
    // tests exercise. It answers nothing here, which is the honest default:
    // none of these tests is about what the network says changed.
    when(() => syncRepository.probeDrivesWithChanges())
        .thenAnswer((_) async => const <String>{});
    userPreferencesRepository = MockUserPreferencesRepository();
    // Every sync that ends writes itself into the history. Unstubbed, that
    // call returns null into a `Future<void>` and the cubit logs a failure it
    // was never meant to have: an error path nobody here is testing.
    when(() => userPreferencesRepository.recordSyncRun(any()))
        .thenAnswer((_) async {});

    // Logged in, so the metadata refresh really reaches updateUserDrives and a
    // full sync really reaches syncAllDrives. A logged-out cubit would take
    // neither path and every assertion below would pass on an absence.
    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(user: getTestUser(), useTurbo: false),
    );
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => profileCubit.refreshBalance()).thenAnswer((_) async {});
    when(() => activityCubit.state).thenReturn(ActivityNotRunning());
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenAnswer((_) => const Stream<void>.empty().listen((_) {}));
    when(() => configService.config).thenReturn(config);
    // No timer and no focus event may fire a sync of its own: the only sync
    // any test here can see is the one the login path decided on.
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => syncRepository.updateUserDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          onDriveRead: any(named: 'onDriveRead'),
          onDriveUnlocked: any(named: 'onDriveUnlocked'),
        )).thenAnswer((_) async {});
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(SyncProgress.emptySyncCompleted()));
    when(() => syncRepository.numberOfFilesInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.numberOfFoldersInWallet())
        .thenAnswer((_) async => 0);
    // Default: the drives here have been walked before, so the only question
    // left is whether an upload is unresolved.
  });

  /// What the local database says about unresolved uploads.

  SyncCubit buildCubit({required bool syncAllDrivesOnLogin}) {
    when(() => userPreferencesRepository.load()).thenAnswer(
      (_) async => UserPreferences(
        currentTheme: ArDriveThemes.dark,
        lastSelectedDriveId: null,
        syncAllDrivesOnLogin: syncAllDrivesOnLogin,
      ),
    );

    return SyncCubit(
      profileCubit: profileCubit,
      activityCubit: activityCubit,
      promptToSnapshotBloc: promptToSnapshotBloc,
      tabVisibility: tabVisibility,
      configService: configService,
      activityTracker: activityTracker,
      syncRepository: syncRepository,
      userPreferencesRepository: userPreferencesRepository,
    );
  }

  test('nothing pending means nothing is asked of the network', () async {
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);

    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.watchForPendingConfirmations();
      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();
    });

    verifyNever(
      () => syncRepository.syncAllDrives(
        wallet: any(named: 'wallet'),
        password: any(named: 'password'),
        cipherKey: any(named: 'cipherKey'),
      ),
    );
  });

  test('and the watch stops rather than asking again', () async {
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);

    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.watchForPendingConfirmations();
      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();
    });

    // Ten intervals would have passed. One local read is the whole cost of an
    // app with no outstanding uploads.
    verify(() => syncRepository.hasPendingTransactions()).called(1);
  });

  test('starting it twice does not double the checking', () async {
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);

    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.watchForPendingConfirmations();
      cubit.watchForPendingConfirmations();
      cubit.watchForPendingConfirmations();
      // Comfortably past one interval, so a second timer would have shown.
      async.elapse(const Duration(minutes: 20));
      async.flushMicrotasks();
    });

    verify(() => syncRepository.hasPendingTransactions()).called(1);
  });

  test('a failed local read stops it rather than spinning', () async {
    when(() => syncRepository.hasPendingTransactions())
        .thenThrow(Exception('database is gone'));

    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.watchForPendingConfirmations();
      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();
    });

    verify(() => syncRepository.hasPendingTransactions()).called(1);
  });

  /// The point of the whole change: an upload is confirmed by asking about
  /// the transaction, never by re-reading every drive the reader owns. A sync
  /// rewrites the rows under an open folder, which is why it locks
  /// multi-select and says the drive is still being read - all of it true of a
  /// sync and none of it true of the question an upload actually raises.
  group('with something pending', () {
    setUp(() {
      // Nothing owed at login: `_syncOnlyIfThereIsWork` runs a full sync when
      // something is pending, which is its job and not this group's subject.
      // Left true from the start, every assertion below would be reading that
      // sync instead of the watch.
      when(() => syncRepository.hasPendingTransactions())
          .thenAnswer((_) async => false);
      when(() => syncRepository.refreshTransactionStatuses(
            ownerAddress: any(named: 'ownerAddress'),
            cancellationToken: any(named: 'cancellationToken'),
          )).thenAnswer((_) async {});
    });

    /// The upload lands after login, which is when the watch is armed.
    void somethingIsPending() {
      when(() => syncRepository.hasPendingTransactions())
          .thenAnswer((_) async => true);
    }

    test('it asks about the transactions, and starts no sync', () async {
      final cubit = buildCubit(syncAllDrivesOnLogin: false);
      addTearDown(cubit.close);
      final states = <SyncState>[];
      final watching = cubit.stream.listen(states.add);
      addTearDown(watching.cancel);

      fakeAsync((async) {
        // Settle the login first, so what follows is the watch alone.
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        states.clear();
        clearInteractions(syncRepository);

        somethingIsPending();
        cubit.watchForPendingConfirmations();
        async.elapse(const Duration(minutes: 1));
        async.flushMicrotasks();
      });

      verify(() => syncRepository.refreshTransactionStatuses(
            ownerAddress: any(named: 'ownerAddress'),
            cancellationToken: any(named: 'cancellationToken'),
          )).called(greaterThanOrEqualTo(1));

      // The property the reader actually sees: no sync ran, so nothing locked
      // multi-select and nothing said the drive was still being read. Asserted
      // on the state rather than on a mock call, because a `verifyNever` whose
      // argument list does not match the real call passes without meaning it.
      expect(
        states.whereType<SyncInProgress>(),
        isEmpty,
        reason: 'confirming an upload must not enter a sync',
      );
    });

    /// A file mined two minutes after it was uploaded used to carry its
    /// pending mark for eighteen more.
    test('the first check comes in well under a minute', () async {
      final cubit = buildCubit(syncAllDrivesOnLogin: false);
      addTearDown(cubit.close);

      fakeAsync((async) {
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        clearInteractions(syncRepository);
        somethingIsPending();

        cubit.watchForPendingConfirmations();
        async.elapse(const Duration(seconds: 29));
        async.flushMicrotasks();
        verifyNever(() => syncRepository.hasPendingTransactions());

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
      });

      verify(() => syncRepository.hasPendingTransactions()).called(1);
    });

    /// It widens as it goes, so a transaction nobody has mined in an hour is
    /// not asked about every thirty seconds, of a gateway that rate limits.
    test('and the wait widens while it stays pending', () async {
      final cubit = buildCubit(syncAllDrivesOnLogin: false);
      addTearDown(cubit.close);

      fakeAsync((async) {
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        clearInteractions(syncRepository);
        somethingIsPending();

        cubit.watchForPendingConfirmations();

        // 30s, then a minute, then two: three checks inside four minutes.
        async.elapse(const Duration(minutes: 4));
        async.flushMicrotasks();
        verify(() => syncRepository.hasPendingTransactions()).called(3);

        // The fourth is five minutes out, not another two.
        async.elapse(const Duration(minutes: 4));
        async.flushMicrotasks();
        verifyNever(() => syncRepository.hasPendingTransactions());

        async.elapse(const Duration(minutes: 2));
        async.flushMicrotasks();
      });

      verify(() => syncRepository.hasPendingTransactions()).called(1);
    });

    test('it stops as soon as nothing is pending', () async {
      final cubit = buildCubit(syncAllDrivesOnLogin: false);
      addTearDown(cubit.close);

      fakeAsync((async) {
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        // Pending for the first round of the watch, settled by the second.
        var checks = 0;
        when(() => syncRepository.hasPendingTransactions())
            .thenAnswer((_) async {
          checks++;
          return checks < 2;
        });

        cubit.watchForPendingConfirmations();
        async.elapse(const Duration(hours: 1));
        async.flushMicrotasks();

        expect(checks, 2, reason: 'the round that found nothing is the last');
      });
    });

    /// One sync at a time is the standing rule, and a running sync answers
    /// this question itself. The round is not spent, so the wait must not
    /// widen: ask again at the same spacing once the sync is over.
    test('a round refused because a sync is running does not widen the wait',
        () async {
      // A sync that starts and never finishes, so the cubit stays in
      // SyncInProgress for the whole test.
      when(() => syncRepository.syncAllDrives(
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: any(named: 'syncDeep'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).thenAnswer((_) => StreamController<SyncProgress>().stream);

      final cubit = buildCubit(syncAllDrivesOnLogin: false);
      addTearDown(cubit.close);

      fakeAsync((async) {
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        unawaited(cubit.startSync());
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(cubit.state, isA<SyncInProgress>());

        clearInteractions(syncRepository);
        somethingIsPending();
        cubit.watchForPendingConfirmations();

        // Thirty seconds apart each time, rather than 30s then a minute.
        async.elapse(const Duration(seconds: 100));
        async.flushMicrotasks();

        verify(() => syncRepository.hasPendingTransactions()).called(3);
        verifyNever(() => syncRepository.refreshTransactionStatuses(
              ownerAddress: any(named: 'ownerAddress'),
              cancellationToken: any(named: 'cancellationToken'),
            ));
      });
    });

    /// A write arms this, and a write means something new is seconds old, so
    /// the schedule starts again from the top rather than from wherever the
    /// last round had widened to.
    test('a later write restarts the schedule', () async {
      final cubit = buildCubit(syncAllDrivesOnLogin: false);
      addTearDown(cubit.close);

      fakeAsync((async) {
        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();
        somethingIsPending();

        cubit.watchForPendingConfirmations();
        // Out to the five-minute step.
        async.elapse(const Duration(minutes: 4));
        async.flushMicrotasks();
        clearInteractions(syncRepository);

        cubit.watchForPendingConfirmations();
        async.elapse(const Duration(seconds: 31));
        async.flushMicrotasks();
      });

      verify(() => syncRepository.hasPendingTransactions()).called(1);
    });
  });
}
