import 'dart:async';

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
          onlyDriveIds: any(named: 'onlyDriveIds'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => progress);
  }

  void driveListReads(Future<void> Function() answer) {
    when(() => syncRepository.updateUserDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          askWalletAgain: any(named: 'askWalletAgain'),
          askWalletAgainFor: any(named: 'askWalletAgainFor'),
          onDriveRead: any(named: 'onDriveRead'),
          onDriveUnlocked: any(named: 'onDriveUnlocked'),
        )).thenAnswer((_) => answer());
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
    driveListReads(() async {});
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
    // The returning-reader probe fires on the same "nothing owed" branch these
    // tests exercise. It answers nothing here, which is the honest default:
    // none of these tests is about what the network says changed.
    when(() => syncRepository.probeDrivesWithChanges())
        .thenAnswer((_) async => const <String>{});
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

  group('a failure says what failed', () {
    test('a drive list that could not be read is a drive-list failure',
        () async {
      driveListReads(() async => throw Exception('the gateway said no'));

      final cubit = buildCubit();
      await cubit.startSync();
      await settle();

      final state = cubit.state as SyncFailure;
      expect(state.kind, SyncFailureKind.driveList);
      expect(state.wasDriveListRefresh, isFalse);
      expect(cubit.driveListRefreshFailed, isTrue);

      await cubit.close();
    });

    test('a sync that read the list and then threw is a sync failure',
        () async {
      repositoryReports(Stream.error(Exception('a parse error')));

      final cubit = buildCubit();
      await cubit.syncDrives(['drive-a', 'drive-b'], deep: true);
      await settle();

      final state = cubit.state as SyncFailure;
      expect(state.kind, SyncFailureKind.sync);
      expect(state.driveIds, ['drive-a', 'drive-b']);
      expect(state.deep, isTrue);
      // The list is as true as it was, so nothing may claim it failed.
      expect(cubit.driveListRefreshFailed, isFalse);

      await cubit.close();
    });

    test('a single drive that threw is named by the failure', () async {
      repositoryReportsForOneDrive(Stream.error(Exception('a parse error')));

      final cubit = buildCubit();
      await cubit.startSyncForDrive(driveId: 'drive-a');
      await settle();

      final state = cubit.state as SyncFailure;
      expect(state.kind, SyncFailureKind.sync);
      expect(state.singleDriveId, 'drive-a');
      expect(cubit.driveListRefreshFailed, isFalse);

      await cubit.close();
    });

    test('a drive-list refresh on its own says so', () async {
      driveListReads(() async => throw Exception('the gateway said no'));

      final cubit = buildCubit();
      await cubit.syncMetadataOnly();

      final state = cubit.state as SyncFailure;
      expect(state.wasDriveListRefresh, isTrue);
      expect(state.kind, SyncFailureKind.driveList);

      await cubit.close();
    });
  });

  group('Try again repeats only what failed', () {
    test('the drive-list refresh, and no sync of any drive', () async {
      driveListReads(() async => throw Exception('the gateway said no'));

      final cubit = buildCubit();
      await cubit.syncMetadataOnly();

      // This time the list arrives, so a retry that went on to sync drives
      // would be seen doing it.
      var reads = 0;
      driveListReads(() async => reads++);
      await cubit.retryFailure();

      expect(reads, 1);
      verifyNever(() => syncRepository.syncAllDrives(
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: any(named: 'syncDeep'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          ));

      await cubit.close();
    });

    test('the same drives, not every drive', () async {
      repositoryReports(Stream.error(Exception('a parse error')));

      final cubit = buildCubit();
      await cubit.syncDrives(['drive-a', 'drive-b']);
      await settle();

      repositoryReports(Stream.value(SyncProgress.emptySyncCompleted()));
      await cubit.retryFailure();

      final calls = verify(() => syncRepository.syncAllDrives(
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: any(named: 'syncDeep'),
            onlyDriveIds: captureAny(named: 'onlyDriveIds'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).captured;
      expect(calls, [
        ['drive-a', 'drive-b'],
        ['drive-a', 'drive-b'],
      ]);

      await cubit.close();
    });

    test('the one drive', () async {
      repositoryReportsForOneDrive(Stream.error(Exception('a parse error')));

      final cubit = buildCubit();
      await cubit.startSyncForDrive(driveId: 'drive-a');
      await settle();

      repositoryReportsForOneDrive(
          Stream.value(SyncProgress.emptySyncCompleted()));
      await cubit.retryFailure();

      final ids = verify(() => syncRepository.syncSingleDrive(
            driveId: captureAny(named: 'driveId'),
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: any(named: 'syncDeep'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).captured;
      expect(ids, ['drive-a', 'drive-a']);

      await cubit.close();
    });
  });

  group('items that could not be read', () {
    test('are read again by a full resync of their drives alone', () async {
      repositoryReports(Stream.value(SyncProgress.initial().copyWith(
        examinedDriveIds: {'drive-a', 'drive-b'},
        syncedDriveIds: ['drive-a', 'drive-b'],
        skippedEntityCount: 1,
        skippedEntityTxIdsByDrive: {
          'drive-a': ['tx-1'],
        },
        progress: 1,
      )));

      final cubit = buildCubit();
      await cubit.startSync();
      expect((cubit.state as SyncComplete).skippedEntityCount, 1);

      repositoryReports(Stream.value(SyncProgress.emptySyncCompleted()));
      expect(await cubit.retrySkippedItems(), isTrue);

      final calls = verify(() => syncRepository.syncAllDrives(
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: captureAny(named: 'syncDeep'),
            onlyDriveIds: captureAny(named: 'onlyDriveIds'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).captured;
      // The second run: deep, because the watermark moved past them, and
      // only over the drive they are in.
      expect(calls[2], isTrue);
      expect(calls[3], ['drive-a']);

      await cubit.close();
    });

    test('and with none waiting, nothing runs', () async {
      final cubit = buildCubit();
      await cubit.startSync();

      expect(await cubit.retrySkippedItems(), isFalse);

      await cubit.close();
    });
  });

  group('a stopped sync', () {
    test('rests as stopped, which every SyncIdle waiter counts as rest',
        () async {
      repositoryReports(_stoppedAfter(SyncProgress.initial().copyWith(
        drivesCount: 3,
        drivesSynced: 1,
      )));

      final cubit = buildCubit();
      await cubit.startSync();
      expect(cubit.state, isA<SyncCancelled>());

      cubit.clearCancelledState();
      final state = cubit.state;
      expect(state, isA<SyncStopped>());
      expect(state, isA<SyncIdle>());
      expect((state as SyncStopped).drivesCompleted, 1);
      expect(state.totalDrives, 3);

      await cubit.close();
    });

    test('marks the drives it opened and did not finish, until one is read',
        () async {
      repositoryReports(_stoppedAfter(SyncProgress.initial().copyWith(
        examinedDriveIds: {'drive-a', 'drive-b'},
        syncedDriveIds: ['drive-a'],
      )));

      final cubit = buildCubit();
      await cubit.startSync();
      expect(cubit.stoppedDriveIds, {'drive-b'});

      // A later sync that reads it to the end takes the mark away.
      repositoryReports(Stream.value(SyncProgress.initial().copyWith(
        examinedDriveIds: {'drive-b'},
        syncedDriveIds: ['drive-b'],
        progress: 1,
      )));
      await cubit.startSync();
      expect(cubit.stoppedDriveIds, isEmpty);

      await cubit.close();
    });

    test('a sync that threw part way marks its unfinished drives too',
        () async {
      final progress = StreamController<SyncProgress>();
      repositoryReports(progress.stream);

      final cubit = buildCubit();
      final run = cubit.startSync();
      await settle();
      progress.add(SyncProgress.initial().copyWith(
        examinedDriveIds: {'drive-a', 'drive-b'},
        syncedDriveIds: ['drive-a'],
      ));
      progress.addError(Exception('a parse error'));
      await progress.close();
      await run;

      expect(cubit.stoppedDriveIds, {'drive-b'});

      await cubit.close();
    });
  });

  group('what is written down', () {
    test('drives the probe found unchanged get a sync time too', () async {
      repositoryReports(Stream.value(SyncProgress.initial().copyWith(
        syncedDriveIds: ['drive-a'],
        unchangedDriveIds: {'drive-b', 'drive-c'},
        progress: 1,
      )));

      final cubit = buildCubit();
      await cubit.startSync();
      await settle();

      final saved = verify(
        () => userPreferencesRepository.saveDrivesLastSynced(captureAny()),
      ).captured.single as List<String>;
      expect(saved.toSet(), {'drive-a', 'drive-b', 'drive-c'});

      await cubit.close();
    });

    test('but not by a sync that did not reach the end', () async {
      final progress = StreamController<SyncProgress>();
      repositoryReports(progress.stream);

      final cubit = buildCubit();
      final run = cubit.startSync();
      await settle();
      progress.add(SyncProgress.initial().copyWith(
        syncedDriveIds: ['drive-a'],
        unchangedDriveIds: {'drive-b'},
      ));
      progress.addError(Exception('a parse error'));
      await progress.close();
      await run;
      await settle();

      final saved = verify(
        () => userPreferencesRepository.saveDrivesLastSynced(captureAny()),
      ).captured.single as List<String>;
      expect(saved, ['drive-a']);

      await cubit.close();
    });

    test('a sync of some drives records how many', () async {
      final cubit = buildCubit();
      await cubit.syncDrives(['drive-a', 'drive-b', 'drive-c']);
      await settle();

      expect(recorded.single.scopedDriveCount, 3);

      await cubit.close();
    });

    test('a sync of every drive records none', () async {
      final cubit = buildCubit();
      await cubit.startSync();
      await settle();

      expect(recorded.single.scopedDriveCount, isNull);

      await cubit.close();
    });
  });
}

/// A sync that reports [progress] and is then stopped.
Stream<SyncProgress> _stoppedAfter(SyncProgress progress) async* {
  yield progress;
  throw SyncCancelledException();
}
