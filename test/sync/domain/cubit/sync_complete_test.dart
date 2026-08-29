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

  /// What the repository reports for the sync under test. The cubit only ever
  /// carries these numbers out; it must not arrive at any of its own.
  void repositoryReports(SyncProgress progress) {
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(progress));
  }

  void repositoryReportsForOneDrive(SyncProgress progress) {
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(progress));
  }

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

    // Logged in, because that is the only profile a sync has a result for -
    // see `loggedOut()` below.
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
        )).thenAnswer((_) async {});
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenAnswer((_) => const Stream<void>.empty().listen((_) {}));
    when(() => configService.config).thenReturn(config);
    // Nothing here may fire a second sync of its own.
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => syncRepository.numberOfFilesInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.numberOfFoldersInWallet())
        .thenAnswer((_) async => 0);
    repositoryReports(SyncProgress.emptySyncCompleted());
  });

  /// A cubit whose login does nothing but load drive metadata, so the only
  /// full syncs in a test are the ones the test starts.
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

  /// No profile behind the sync. Nothing was read, so there is nothing to
  /// report - and 'up to date' would be a claim about drives never looked at.
  void loggedOut() {
    when(() => profileCubit.state).thenReturn(ProfileCheckingAvailability());
  }

  /// Every result the cubit reported while [act] ran.
  Future<List<SyncComplete>> resultsOf(
    SyncCubit cubit,
    Future<void> Function() act,
  ) async {
    final results = <SyncComplete>[];
    final subscription = cubit.stream.listen((state) {
      if (state is SyncComplete) {
        results.add(state);
      }
    });

    await act();
    // The cubit hands its states to listeners on a later microtask, so the
    // last result of the run is still in flight when act() returns.
    await Future<void>.delayed(Duration.zero);
    await subscription.cancel();

    return results;
  }

  test('a finished sync is still an idle sync', () {
    // The contract this whole state hangs on. DriveDetailCubit refreshes the
    // open drive on `syncState is SyncIdle`, and SharingFileListener hands a
    // shared file over on the same test. A sibling state would leave both
    // waiting on a sync that had already finished, with nothing to show for
    // it - so the result is a kind of idle, not an alternative to it.
    final result = SyncComplete(
      entitiesSynced: 0,
      completedAt: DateTime.now(),
      sequence: 1,
    );

    expect(result, isA<SyncIdle>());
  });

  test('two results that read the same are still two results', () {
    // Bloc drops a state equal to the one it is already in. Two syncs that
    // both found nothing carry identical counts, so without something that
    // tells them apart the second result could go unreported - and the sync
    // that changed nothing is the one most worth hearing about.
    //
    // Deliberately at the same instant: two mocked syncs with no I/O between
    // them land in the same millisecond, and a millisecond-grained timestamp
    // is therefore not something that tells them apart.
    final sameInstant = DateTime(2026, 8, 29, 10);
    final first = SyncComplete(
      entitiesSynced: 0,
      completedAt: sameInstant,
      sequence: 1,
    );
    final second = SyncComplete(
      entitiesSynced: 0,
      completedAt: sameInstant,
      sequence: 2,
    );

    expect(second, isNot(equals(first)));
  });

  test('a finished sync carries the counts the repository reported', () async {
    repositoryReports(
      SyncProgress.initial().copyWith(
        progress: 1,
        entitiesSynced: 12,
        drivesSynced: 3,
        drivesCount: 3,
        skippedEntityCount: 2,
        skippedEntityTxIdsByDrive: const {
          'drive-id': ['tx-one', 'tx-two'],
        },
      ),
    );

    final cubit = buildCubit();
    final results = await resultsOf(cubit, () => cubit.startSync());
    await cubit.close();

    expect(results, hasLength(1));
    expect(results.single.entitiesSynced, 12);
    expect(results.single.skippedEntityCount, 2);
    expect(results.single.trigger, SyncTrigger.userInitiated);
  });

  test('a sync of one drive reports the drive it was', () async {
    repositoryReportsForOneDrive(
      SyncProgress.initial().copyWith(
        progress: 1,
        entitiesSynced: 4,
        drivesSynced: 1,
        drivesCount: 1,
        isSingleDriveSync: true,
        driveName: 'Photos',
      ),
    );

    final cubit = buildCubit();
    final results = await resultsOf(
      cubit,
      () => cubit.startSyncForDrive(driveId: 'drive-id'),
    );
    await cubit.close();

    expect(results, hasLength(1));
    expect(results.single.isSingleDriveSync, isTrue);
    expect(results.single.driveName, 'Photos');
    expect(results.single.entitiesSynced, 4);
  });

  test('a background sync reports itself as one nobody asked for', () async {
    final cubit = buildCubit();
    final results = await resultsOf(
      cubit,
      () => cubit.startSync(trigger: SyncTrigger.background),
    );
    await cubit.close();

    expect(results.single.trigger, SyncTrigger.background);
  });

  test('two zero-change syncs in a row both report', () async {
    final cubit = buildCubit();

    final results = await resultsOf(cubit, () async {
      await cubit.startSync();
      await cubit.startSync();
    });
    await cubit.close();

    expect(results, hasLength(2));
    expect(results.first.entitiesSynced, 0);
    expect(results.last.entitiesSynced, 0);
    // And they are two states, not one reported twice: a UI that keys on the
    // result cannot show the second one otherwise. Nothing here does any I/O,
    // so the two land in the same millisecond often enough that a timestamp
    // would drop one at random - the sequence is what separates them.
    expect(results.last, isNot(equals(results.first)));
    expect(results.first.sequence, 1);
    expect(results.last.sequence, 2);
  });

  group('a sync that did not finish claims nothing', () {
    // The catch reports the error and falls through to the block that decides
    // what to emit. A sync that threw before any drive query ran records no
    // failedQueries, so that block used to read "no errors, nothing synced"
    // and announce "Up to date - nothing new" next to the snackbar saying the
    // sync failed.

    test('the all-drives path reports no result when it throws', () async {
      when(() => syncRepository.updateUserDrives(
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
          )).thenThrow(Exception('the gateway said no'));

      final cubit = buildCubit();
      final states = <SyncState>[];
      final subscription = cubit.stream.listen(states.add);

      await cubit.startSync();
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      await cubit.close();

      expect(states.whereType<SyncComplete>(), isEmpty);
      expect(states.whereType<SyncFailure>(), isNotEmpty,
          reason: 'the failure is still reported as a failure');
      expect(cubit.state, isA<SyncIdle>());
      expect(cubit.state, isNot(isA<SyncComplete>()));
    });

    test('the single-drive path reports no result when it throws', () async {
      when(() => syncRepository.syncSingleDrive(
            driveId: any(named: 'driveId'),
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: any(named: 'syncDeep'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).thenAnswer(
        (_) => Stream<SyncProgress>.error(Exception('the gateway said no')),
      );

      final cubit = buildCubit();
      final results = await resultsOf(
        cubit,
        () => cubit.startSyncForDrive(driveId: 'drive-id'),
      );

      expect(results, isEmpty);
      expect(cubit.state, isA<SyncIdle>());
      expect(cubit.state, isNot(isA<SyncComplete>()));

      await cubit.close();
    });

    test('a sync with nobody logged in reports no result', () async {
      loggedOut();

      final cubit = buildCubit();
      final results = await resultsOf(cubit, () => cubit.startSync());

      expect(results, isEmpty);
      expect(cubit.state, isA<SyncIdle>());
      expect(cubit.state, isNot(isA<SyncComplete>()));

      await cubit.close();
    });

    test('a single drive sync with nobody logged in reports no result',
        () async {
      loggedOut();
      repositoryReportsForOneDrive(
        SyncProgress.initial().copyWith(progress: 1, drivesCount: 1),
      );

      final cubit = buildCubit();
      final results = await resultsOf(
        cubit,
        () => cubit.startSyncForDrive(driveId: 'drive-id'),
      );

      expect(results, isEmpty);
      expect(cubit.state, isA<SyncIdle>());
      expect(cubit.state, isNot(isA<SyncComplete>()));

      await cubit.close();
    });
  });
}
