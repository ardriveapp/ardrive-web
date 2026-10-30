// The sync that follows an unlock, on SyncCubit's own harness
// (sync_one_at_a_time_test.dart): it runs although the tab has no focus,
// and it waits for whatever refused it.
import 'dart:async';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_dialog.dart';
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
    userPreferencesRepository = MockUserPreferencesRepository();

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(user: getTestUser(), useTurbo: false),
    );
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => profileCubit.refreshBalance()).thenAnswer((_) async {});
    when(() => activityCubit.state).thenReturn(ActivityNotRunning());
    when(() => syncRepository.updateUserDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          askWalletAgain: any(named: 'askWalletAgain'),
          askWalletAgainFor: any(named: 'askWalletAgainFor'),
        )).thenAnswer((_) async {});
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenAnswer((_) => const Stream<void>.empty().listen((_) {}));
    when(() => configService.config).thenReturn(config);
    // Nothing here may fire a sync of its own.
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => syncRepository.numberOfFilesInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.numberOfFoldersInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);
    // The returning-reader probe fires on the same "nothing owed" branch these
    // tests exercise. It answers nothing here, which is the honest default:
    // none of these tests is about what the network says changed.
    when(() => syncRepository.probeDrivesWithChanges())
        .thenAnswer((_) async => const <String>{});
    when(() => userPreferencesRepository.saveDrivesLastSynced(any()))
        .thenAnswer((_) async {});
  });

  SyncCubit buildCubit() {
    when(() => userPreferencesRepository.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.dark,
        lastSelectedDriveId: null,
        syncAllDrivesOnLogin: false,
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

  /// Lets the cubit's own login path - `syncMetadataOnly`, which every
  /// constructor runs - finish before a test starts a sync of its own.
  /// Without this it is the login path's `SyncIdle` that lands last.
  Future<void> settled() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  void stubSyncAllDrives() => when(() => syncRepository.syncAllDrives(
        syncDeep: any(named: 'syncDeep'),
        wallet: any(named: 'wallet'),
        password: any(named: 'password'),
        cipherKey: any(named: 'cipherKey'),
        cancellationToken: any(named: 'cancellationToken'),
        onlyDriveIds: any(named: 'onlyDriveIds'),
        txFechedCallback: any(named: 'txFechedCallback'),
      )).thenAnswer((_) => Stream.value(SyncProgress.emptySyncCompleted()));

  void verifySynced(List<String> driveIds, {int times = 1}) =>
      verify(() => syncRepository.syncAllDrives(
            syncDeep: any(named: 'syncDeep'),
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            cancellationToken: any(named: 'cancellationToken'),
            onlyDriveIds: driveIds,
            txFechedCallback: any(named: 'txFechedCallback'),
          )).called(times);

  // Wander's approval window in front of the tab takes the focus away
  // (document.hasFocus() is false), at exactly the moment the unlock ends.
  test('Wander, tab without focus: the sync after an unlock still runs',
      () async {
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => true);
    when(() => profileCubit.logoutIfWalletMismatchInBackground())
        .thenAnswer((_) async => false);
    stubSyncAllDrives();
    final cubit = buildCubit();
    await settled();
    when(() => tabVisibility.isTabFocused()).thenReturn(false);

    await syncUnlockedDrives(cubit, ['just-unlocked']);

    verifySynced(['just-unlocked']);
    await cubit.close();
  });

  test(
      'an upload running: the sync after an unlock waits for it to end, '
      'then runs', () async {
    stubSyncAllDrives();
    final cubit = buildCubit();
    await settled();

    final activity = StreamController<ActivityState>.broadcast();
    when(() => activityCubit.state).thenReturn(ActivityInProgress());
    when(() => activityCubit.stream).thenAnswer((_) => activity.stream);

    var done = false;
    final sync =
        syncUnlockedDrives(cubit, ['just-unlocked']).then((_) => done = true);
    await settled();
    expect(done, isFalse, reason: 'it gave up instead of waiting');
    verifyNever(() => syncRepository.syncAllDrives(
          syncDeep: any(named: 'syncDeep'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          cancellationToken: any(named: 'cancellationToken'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          txFechedCallback: any(named: 'txFechedCallback'),
        ));

    when(() => activityCubit.state).thenReturn(ActivityNotRunning());
    activity.add(ActivityNotRunning());
    await sync;

    verifySynced(['just-unlocked']);
    await activity.close();
    await cubit.close();
  });

  test(
      'another sync running: the sync after an unlock waits for it, then '
      'runs', () async {
    final running = StreamController<SyncProgress>();
    var calls = 0;
    when(() => syncRepository.syncAllDrives(
              syncDeep: any(named: 'syncDeep'),
              wallet: any(named: 'wallet'),
              password: any(named: 'password'),
              cipherKey: any(named: 'cipherKey'),
              cancellationToken: any(named: 'cancellationToken'),
              onlyDriveIds: any(named: 'onlyDriveIds'),
              txFechedCallback: any(named: 'txFechedCallback'),
            ))
        .thenAnswer((_) => calls++ == 0
            ? running.stream
            : Stream.value(SyncProgress.emptySyncCompleted()));
    final cubit = buildCubit();
    await settled();

    unawaited(cubit.startSync(trigger: SyncTrigger.background));
    await settled();
    expect(cubit.state, isA<SyncInProgress>());

    final sync = syncUnlockedDrives(cubit, ['just-unlocked']);
    await settled();
    running
      ..add(SyncProgress.emptySyncCompleted())
      ..close();
    await sync;

    verifySynced(['just-unlocked']);
    await cubit.close();
  });

  test('with focus: the unlocked drive alone is synced', () async {
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => true);
    when(() => profileCubit.logoutIfWalletMismatchInBackground())
        .thenAnswer((_) async => false);
    when(() => syncRepository.syncAllDrives(
          syncDeep: any(named: 'syncDeep'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          cancellationToken: any(named: 'cancellationToken'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(SyncProgress.emptySyncCompleted()));
    final cubit = buildCubit();
    await settled();

    await syncUnlockedDrives(cubit, ['just-unlocked']);

    verify(() => syncRepository.syncAllDrives(
          syncDeep: any(named: 'syncDeep'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          cancellationToken: any(named: 'cancellationToken'),
          onlyDriveIds: ['just-unlocked'],
          txFechedCallback: any(named: 'txFechedCallback'),
        )).called(1);
    await cubit.close();
  });
}
