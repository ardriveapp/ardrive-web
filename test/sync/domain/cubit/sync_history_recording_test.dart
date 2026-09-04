import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/domain/sync_run.dart';
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

class _FakeSyncRun extends Fake implements SyncRun {}

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

  /// Every run the cubit wrote down, in the order it wrote them.
  late List<SyncRun> recorded;

  setUpAll(() {
    registerFallbackValue(false);
    registerFallbackValue(_FakeWallet());
    registerFallbackValue(_FakeSecretKey());
    registerFallbackValue(_FakeSyncRun());
  });

  void repositoryReports(Stream<SyncProgress> progress) {
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => progress);
  }

  void repositoryReportsForOneDrive(Stream<SyncProgress> progress) {
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => progress);
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
    recorded = [];

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
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => syncRepository.numberOfFilesInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.numberOfFoldersInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);
    when(() => userPreferencesRepository.saveDrivesLastSynced(any()))
        .thenAnswer((_) async {});
    when(() => userPreferencesRepository.recordSyncRun(any()))
        .thenAnswer((invocation) async {
      recorded.add(invocation.positionalArguments.first as SyncRun);
    });

    repositoryReports(Stream.value(SyncProgress.emptySyncCompleted()));
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

  /// The cubit records its run on a future it does not await, exactly like the
  /// per-drive timestamps beside it, so the write is still in flight when the
  /// sync returns.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('a sync that finished is written down with what it found', () async {
    repositoryReports(Stream.value(
      SyncProgress.initial().copyWith(
        entitiesSynced: 12,
        drivesCount: 3,
        progress: 1,
      ),
    ));

    final cubit = buildCubit();
    await cubit.startSync(trigger: SyncTrigger.background);
    await settle();

    expect(recorded, hasLength(1));
    expect(recorded.single.outcome, SyncRunOutcome.completed);
    expect(recorded.single.trigger, SyncTrigger.background);
    expect(recorded.single.itemsFound, 12);
    expect(recorded.single.totalDrives, 3);
    expect(recorded.single.driveName, isNull,
        reason: 'a sync of every drive has no one drive to name');
    // Counted from the sync's own start, and closed off when it ended - the
    // same instant the elapsed counter on the indicator was counting from.
    expect(recorded.single.startedAt, cubit.syncStartTime);
    expect(recorded.single.took.isNegative, isFalse);
    expect(
      recorded.single.startedAt.add(recorded.single.took).isAfter(
            DateTime.now(),
          ),
      isFalse,
      reason: 'a sync cannot have finished in the future',
    );

    await cubit.close();
  });

  test('a sync of one drive is written down with the drive it was for',
      () async {
    repositoryReportsForOneDrive(Stream.value(
      SyncProgress.initial().copyWith(
        isSingleDriveSync: true,
        driveName: 'Family Photos',
        entitiesSynced: 4,
        drivesCount: 1,
        progress: 1,
      ),
    ));

    final cubit = buildCubit();
    await cubit.startSyncForDrive(
      driveId: 'drive-a',
      trigger: SyncTrigger.userInitiated,
    );
    await settle();

    expect(recorded, hasLength(1));
    expect(recorded.single.driveName, 'Family Photos');
    expect(recorded.single.trigger, SyncTrigger.userInitiated);
    expect(recorded.single.itemsFound, 4);

    await cubit.close();
  });

  test('a sync that failed outright keeps the reason it failed', () async {
    // The one entry a user opens Troubleshooting to read. errorMessages only
    // carries PER-DRIVE failures, so a sync that died before it reached any
    // drive had none - and the record said only "this sync could not be done",
    // which is the sentence the user already knew.
    repositoryReports(Stream<SyncProgress>.error(
      Exception('the gateway refused the connection'),
    ));

    final cubit = buildCubit();
    await cubit.startSync();
    await settle();

    expect(recorded, hasLength(1));
    expect(recorded.single.outcome, SyncRunOutcome.failed);
    expect(
      recorded.single.errorMessages.values.join(),
      contains('the gateway refused the connection'),
      reason: 'the record carried no reason for the failure',
    );

    await cubit.close();
  });

  test('a sync with drives it could not read keeps the error text', () async {
    repositoryReports(Stream.value(
      SyncProgress.initial().copyWith(
        entitiesSynced: 5,
        drivesCount: 5,
        failedQueries: 2,
        failedDriveIds: const ['drive-a', 'drive-b'],
        errorMessages: const {'drive-a': 'the gateway said no'},
        skippedEntityCount: 3,
        progress: 1,
      ),
    ));

    final cubit = buildCubit();
    await cubit.startSync();
    await settle();

    expect(recorded, hasLength(1));
    expect(recorded.single.outcome, SyncRunOutcome.completedWithErrors);
    expect(recorded.single.failedDrives, 2);
    expect(recorded.single.totalDrives, 5);
    expect(recorded.single.skippedEntityCount, 3);
    // Verbatim: a user reading this is a button away from sending the logs
    // beside it to support, and a paraphrase is not searchable.
    expect(recorded.single.errorMessages, {'drive-a': 'the gateway said no'});

    await cubit.close();
  });

  test('a sync that was stopped part way is written down as stopped', () async {
    repositoryReports(Stream.error(SyncCancelledException()));

    final cubit = buildCubit();
    await cubit.startSync();
    await settle();

    expect(recorded, hasLength(1));
    expect(recorded.single.outcome, SyncRunOutcome.cancelled);

    await cubit.close();
  });

  test('a sync that threw is written down as one that failed', () async {
    repositoryReports(Stream.error(Exception('the gateway said no')));

    final cubit = buildCubit();
    await cubit.startSync();
    await settle();

    expect(recorded, hasLength(1));
    expect(recorded.single.outcome, SyncRunOutcome.failed);

    await cubit.close();
  });

  test('a sync that was refused before it started is not written down at all',
      () async {
    // Nothing was fetched, so there is nothing to say about it - and a history
    // full of runs that never happened is a history nobody can read.
    when(() => activityCubit.state).thenReturn(ActivityInProgress());

    final cubit = buildCubit();
    final ran = await cubit.startSync();
    await settle();

    expect(ran, isFalse, reason: 'precondition: the sync was refused');
    expect(recorded, isEmpty);

    await cubit.close();
  });

  test('a history write that fails does not take the finished sync with it',
      () async {
    when(() => userPreferencesRepository.recordSyncRun(any()))
        .thenThrow(Exception('the store is full'));
    repositoryReports(Stream.value(
      SyncProgress.initial().copyWith(entitiesSynced: 12, progress: 1),
    ));

    final cubit = buildCubit();
    final ran = await cubit.startSync(trigger: SyncTrigger.background);
    await settle();

    expect(ran, isTrue);
    expect(cubit.state, isA<SyncComplete>());
    expect((cubit.state as SyncComplete).entitiesSynced, 12);

    await cubit.close();
  });
}
