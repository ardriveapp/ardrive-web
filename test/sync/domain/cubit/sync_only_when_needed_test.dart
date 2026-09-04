import 'dart:async';

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

import '../../../test_utils/utils.dart';

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

  /// Completes the first time the cubit asks whether anything is pending, so
  /// a test waits for the decision to have been made rather than for a slice
  /// of wall clock a loaded box can spend without reaching it.
  late Completer<void> pendingWasChecked;

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
    userPreferencesRepository = MockUserPreferencesRepository();
    pendingWasChecked = Completer<void>();

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
        )).thenAnswer((_) async {});
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
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
  void nothingIsPending() {
    when(() => syncRepository.hasPendingTransactions()).thenAnswer((_) async {
      if (!pendingWasChecked.isCompleted) pendingWasChecked.complete();
      return false;
    });
  }

  void somethingIsPending() {
    when(() => syncRepository.hasPendingTransactions()).thenAnswer((_) async {
      if (!pendingWasChecked.isCompleted) pendingWasChecked.complete();
      return true;
    });
  }

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

  /// Every trigger a full sync reported while the login path settled.
  ///
  /// [waitForPendingCheck] is how a test that expects NO sync still knows the
  /// decision was reached: without it the assertion could pass simply because
  /// the login path had not got that far yet.
  Future<List<SyncTrigger>> loginTriggers(
    SyncCubit cubit, {
    bool waitForPendingCheck = true,
  }) async {
    final triggers = <SyncTrigger>[];
    final subscription = cubit.stream.listen((state) {
      if (state is SyncInProgress) triggers.add(state.trigger);
    });

    if (waitForPendingCheck) {
      await pendingWasChecked.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => fail('the cubit never asked whether work was pending'),
      );
    }

    // Let whatever the decision was actually happen.
    await pumpEventQueue(times: 100);
    await subscription.cancel();

    return triggers;
  }

  test('a quiet login refreshes the drive list and syncs nothing', () async {
    nothingIsPending();
    final cubit = buildCubit(syncAllDrivesOnLogin: false);

    final triggers = await loginTriggers(cubit);
    await cubit.close();

    // Nothing walked any drive's history.
    verifyNever(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        ));
    expect(triggers, isEmpty);

    // But not syncing must not mean not noticing drives: updateUserDrives is
    // what makes a drive created or renamed elsewhere appear, and it still
    // runs - exactly once, since no full sync ran to call it a second time.
    verify(() => syncRepository.updateUserDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
        )).called(1);
  });

  test('an upload left unresolved makes the login sync anyway', () async {
    // Nothing but a sync resolves a pending transaction, so this is the one
    // case where there is real work and the login has to do it.
    somethingIsPending();
    final cubit = buildCubit(syncAllDrivesOnLogin: false);

    final triggers = await loginTriggers(cubit);
    await cubit.close();

    verify(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).called(1);

    // Nobody asked for it, so it may not hold the app - the whole surface
    // beneath this depends on a login sync being a background one.
    expect(triggers, [SyncTrigger.background]);
  });

  test('the user who opted in still gets the full sync', () async {
    // The preference is an explicit yes; the pending check is not consulted
    // and could not have caused this sync.
    nothingIsPending();
    final cubit = buildCubit(syncAllDrivesOnLogin: true);

    final triggers = await loginTriggers(cubit, waitForPendingCheck: false);
    await cubit.close();

    verify(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).called(1);
    verifyNever(() => syncRepository.hasPendingTransactions());
    expect(triggers, [SyncTrigger.background]);
  });
  test('an empty database is not a reason to override the setting', () async {
    // A first login with the setting off shows the drive list with no
    // contents, and each drive opens on the "Drive Not Synced" card with its
    // own Sync button. Syncing anyway overrode an explicit choice to protect
    // the user from a state they asked for - and on a fresh browser profile it
    // made the setting look broken, because every first run took that branch.
    nothingIsPending();

    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    addTearDown(cubit.close);

    await pendingWasChecked.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the cubit never asked whether work was owed'),
    );
    await pumpEventQueue();

    verifyNever(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        ));

    // The drive list still arrives - not syncing must not mean not noticing.
    verify(() => syncRepository.updateUserDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
        )).called(1);
  });
  test('one drive left unsynced does not drag the wallet through a sync',
      () async {
    // The regression: the escape hatch asked "is any drive unsynced", which a
    // freshly attached drive - or one that keeps failing - makes true forever,
    // so turning the setting off stopped meaning anything.
    nothingIsPending();
    final cubit = buildCubit(syncAllDrivesOnLogin: false);
    addTearDown(cubit.close);

    await pendingWasChecked.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => fail('the cubit never asked whether work was owed'),
    );
    await pumpEventQueue();

    verifyNever(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        ));
  });
}
