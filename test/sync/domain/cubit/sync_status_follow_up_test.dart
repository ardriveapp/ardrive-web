import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
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

import '../../../test_utils/utils.dart';

class MockSyncRepository extends Mock implements SyncRepository {}

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class MockActivityTracker extends Mock implements ActivityTracker {}

class _FakeWallet extends Fake implements Wallet {}

class _FakeSecretKey extends Fake implements SecretKey {}

class _FakeSyncRun extends Fake implements SyncRun {}

/// A sync whose status pass ran out of time still owes the rest of the
/// confirming. The sync reports done on time; the cubit then finishes the job
/// outside it, through the same one-at-a-time refresh the confirmation watch
/// already uses, instead of leaving the rows pending until some later sync.
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
          askWalletAgain: any(named: 'askWalletAgain'),
          askWalletAgainFor: any(named: 'askWalletAgainFor'),
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

  /// A run that ended with its status pass cut short, or not.
  void syncReports({required bool timedOut}) {
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(
          SyncProgress.emptySyncCompleted()
              .copyWith(statusPassTimedOut: timedOut),
        ));
  }

  void refreshRuns(Future<void> Function(SyncCancellationToken?) onRefresh) {
    when(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).thenAnswer((invocation) => onRefresh(
          invocation.namedArguments[#cancellationToken]
              as SyncCancellationToken?,
        ));
  }

  setUp(() {
    // Nothing owed at login: a pending transaction there starts a sync of its
    // own, which is not what these tests are about. See [owedFromNowOn].
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);
  });

  /// Builds the cubit, lets its login settle, and only then marks something
  /// as pending, so the sync under test is the only one that runs.
  Future<SyncCubit> cubitOwedFromNowOn() async {
    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => true);
    return cubit;
  }

  test('a sync whose status pass timed out is followed by a refresh', () async {
    syncReports(timedOut: true);
    refreshRuns((_) async {});
    final cubit = await cubitOwedFromNowOn();
    addTearDown(cubit.close);

    fakeAsync((async) {
      bool? synced;
      cubit.startSync().then((ran) => synced = ran);
      async.flushMicrotasks();
      expect(synced, isTrue);
      // The sync is over and nothing has been asked yet: the follow-up is
      // outside it, never inside it.
      verifyNever(() => syncRepository.refreshTransactionStatuses(
            ownerAddress: any(named: 'ownerAddress'),
            cancellationToken: any(named: 'cancellationToken'),
          ));

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
    });

    verify(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).called(1);
  });

  test('a single drive sync that timed out is followed by a refresh too',
      () async {
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          syncDeep: any(named: 'syncDeep'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(
          SyncProgress.emptySyncCompleted().copyWith(statusPassTimedOut: true),
        ));
    refreshRuns((_) async {});
    final cubit = await cubitOwedFromNowOn();
    addTearDown(cubit.close);

    fakeAsync((async) {
      bool? synced;
      cubit.startSyncForDrive(driveId: 'drive').then((ran) => synced = ran);
      async.flushMicrotasks();
      expect(synced, isTrue);
      verifyNever(() => syncRepository.refreshTransactionStatuses(
            ownerAddress: any(named: 'ownerAddress'),
            cancellationToken: any(named: 'cancellationToken'),
          ));

      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
    });

    verify(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        )).called(1);
  });

  test('a sync whose status pass finished is not followed by anything',
      () async {
    syncReports(timedOut: false);
    final cubit = await cubitOwedFromNowOn();
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.startSync();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 30));
      async.flushMicrotasks();
    });

    verifyNever(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        ));
  });

  test('no second pass starts while the follow-up is still running', () async {
    syncReports(timedOut: true);
    var started = 0;
    final slow = Completer<void>();
    refreshRuns((_) {
      started++;
      return slow.future;
    });
    final cubit = await cubitOwedFromNowOn();
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.startSync();
      async.flushMicrotasks();
      // Far past every step of the watch's schedule: it only rounds again
      // once a pass has returned.
      async.elapse(const Duration(hours: 2));
      async.flushMicrotasks();
    });

    expect(started, 1);
    slow.complete();
  });

  test('a new sync stops a follow-up that is still running', () async {
    syncReports(timedOut: true);
    SyncCancellationToken? followUp;
    refreshRuns((token) {
      followUp = token;
      return Completer<void>().future;
    });
    final cubit = await cubitOwedFromNowOn();
    addTearDown(cubit.close);

    fakeAsync((async) {
      cubit.startSync();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(followUp, isNotNull);
      expect(followUp!.isCancelled, isFalse);

      cubit.startSync();
      async.flushMicrotasks();
    });

    expect(followUp!.isCancelled, isTrue);
  });

  test('closing the cubit stops the follow-up, running or not yet started',
      () async {
    syncReports(timedOut: true);
    SyncCancellationToken? followUp;
    var started = 0;
    refreshRuns((token) {
      started++;
      followUp = token;
      return Completer<void>().future;
    });
    final cubit = await cubitOwedFromNowOn();

    fakeAsync((async) {
      cubit.startSync();
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      async.flushMicrotasks();
      expect(followUp!.isCancelled, isFalse);

      cubit.close();
      async.flushMicrotasks();
      expect(followUp!.isCancelled, isTrue);

      async.elapse(const Duration(hours: 2));
      async.flushMicrotasks();
    });

    expect(started, 1);
  });

  test('closing before the follow-up fires means it never fires', () async {
    syncReports(timedOut: true);
    refreshRuns((_) async {});
    final cubit = await cubitOwedFromNowOn();

    fakeAsync((async) {
      cubit.startSync();
      async.flushMicrotasks();
      cubit.close();
      async.flushMicrotasks();
      async.elapse(const Duration(hours: 2));
      async.flushMicrotasks();
    });

    verifyNever(() => syncRepository.refreshTransactionStatuses(
          ownerAddress: any(named: 'ownerAddress'),
          cancellationToken: any(named: 'cancellationToken'),
        ));
  });
}
