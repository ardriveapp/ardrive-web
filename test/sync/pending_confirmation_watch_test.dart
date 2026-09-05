import 'dart:async';

import 'package:fake_async/fake_async.dart';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
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
}
