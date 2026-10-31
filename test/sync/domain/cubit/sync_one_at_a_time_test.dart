import 'dart:async';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
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

  /// A single-drive sync that does not finish until [finish] is completed, so
  /// a test can ask a second one to start while the first is still running.
  Completer<void> aSingleDriveSyncThatHangs() {
    final finish = Completer<void>();

    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer(
      (_) => Stream.fromFuture(
        finish.future.then((_) => SyncProgress.emptySyncCompleted()),
      ),
    );

    return finish;
  }

  test('a second single-drive sync is refused outright, not queued', () async {
    // The old guard awaited the running sync and re-checked afterwards, so a
    // second request either waited invisibly for minutes or was silently
    // discarded depending on what had started meanwhile - and from the outside
    // those two are indistinguishable. One at a time, no queue.
    final finish = aSingleDriveSyncThatHangs();

    final cubit = buildCubit();
    await settled();

    final first = cubit.startSyncForDrive(driveId: 'drive-a');
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<SyncInProgress>(),
        reason: 'precondition: a sync is running');

    // The refusal returns rather than waiting: this future completes while the
    // first sync is still running.
    await cubit.startSyncForDrive(driveId: 'drive-b').timeout(
          const Duration(seconds: 1),
          onTimeout: () =>
              fail('the second request waited instead of refusing'),
        );

    verifyNever(() => syncRepository.syncSingleDrive(
          driveId: 'drive-b',
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        ));

    // And the sync that was already running is untouched by the refusal.
    expect(cubit.syncingDriveId, 'drive-a');

    finish.complete();
    await first;
    await cubit.close();
  });

  test('the refusal says so, rather than looking like a sync that ran',
      () async {
    // Every caller that awaits this reads the drive afterwards and reports
    // what the sync found. A refusal that is indistinguishable from a
    // completed sync becomes "the sync looked and found nothing" about a sync
    // that never started - see `DriveDetailCubit.syncCurrentDrive`.
    final finish = aSingleDriveSyncThatHangs();

    final cubit = buildCubit();
    await settled();

    final first = cubit.startSyncForDrive(driveId: 'drive-a');
    await Future<void>.delayed(Duration.zero);

    expect(
      await cubit.startSyncForDrive(driveId: 'drive-b'),
      isFalse,
      reason: 'nothing was started for drive-b',
    );

    finish.complete();
    expect(await first, isTrue, reason: 'and this one did run');

    await cubit.close();
  });

  test('the refusal does not disturb the sync already running', () async {
    final finish = aSingleDriveSyncThatHangs();

    final cubit = buildCubit();
    await settled();

    final first = cubit.startSyncForDrive(driveId: 'drive-a');
    await Future<void>.delayed(Duration.zero);

    await cubit.startSyncForDrive(driveId: 'drive-b');

    finish.complete();
    await first;
    await Future<void>.delayed(Duration.zero);

    // One sync ran, it ran for drive-a, and it finished.
    verify(() => syncRepository.syncSingleDrive(
          driveId: 'drive-a',
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).called(1);
    expect(cubit.state, isA<SyncComplete>());
    expect(cubit.syncingDriveId, isNull);

    await cubit.close();
  });

  test('a single-drive sync still runs when nothing else is', () async {
    // The refusal must not be the only thing this method does.
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => Stream.value(SyncProgress.emptySyncCompleted()));

    final cubit = buildCubit();
    await settled();

    expect(await cubit.startSyncForDrive(driveId: 'drive-a'), isTrue);
    await Future<void>.delayed(Duration.zero);

    verify(() => syncRepository.syncSingleDrive(
          driveId: 'drive-a',
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).called(1);

    await cubit.close();
  });

  group('wallet prompts cancelled earlier', () {
    void allDrivesSyncAtOnce() {
      when(() => syncRepository.syncAllDrives(
            syncDeep: any(named: 'syncDeep'),
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            cancellationToken: any(named: 'cancellationToken'),
            onlyDriveIds: any(named: 'onlyDriveIds'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).thenAnswer((_) => Stream.value(SyncProgress.emptySyncCompleted()));
    }

    /// What the last drive-list refresh was told about asking again.
    ({bool? all, Iterable<String>? only}) lastAsk() {
      final captured = verify(() => syncRepository.updateUserDrives(
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            askWalletAgain: captureAny(named: 'askWalletAgain'),
            askWalletAgainFor: captureAny(named: 'askWalletAgainFor'),
          )).captured;
      return (
        all: captured[captured.length - 2] as bool?,
        only: captured.last as Iterable<String>?,
      );
    }

    test('a sync the user starts asks again for every drive', () async {
      allDrivesSyncAtOnce();
      final cubit = buildCubit();
      await settled();

      await cubit.startSync();

      expect(lastAsk().all, isTrue);
      await cubit.close();
    });

    test(
        'the sync after an unlock does not: unlocking one drive is not a '
        'request to be prompted for the others', () async {
      allDrivesSyncAtOnce();
      final cubit = buildCubit();
      await settled();

      await cubit.syncDrives(['unlocked'], askWalletAgain: false);

      expect(lastAsk().all, isFalse);
      await cubit.close();
    });

    test('syncing one drive asks again for that drive only', () async {
      when(() => syncRepository.syncSingleDrive(
            driveId: any(named: 'driveId'),
            wallet: any(named: 'wallet'),
            password: any(named: 'password'),
            cipherKey: any(named: 'cipherKey'),
            syncDeep: any(named: 'syncDeep'),
            cancellationToken: any(named: 'cancellationToken'),
            txFechedCallback: any(named: 'txFechedCallback'),
          )).thenAnswer((_) => Stream.value(SyncProgress.emptySyncCompleted()));
      final cubit = buildCubit();
      await settled();

      await cubit.startSyncForDrive(driveId: 'drive-a');

      final ask = lastAsk();
      expect(ask.all, isFalse);
      expect(ask.only, ['drive-a']);
      await cubit.close();
    });

    // Try again after some drives failed. A drive whose prompt was cancelled
    // but which did not fail is not part of what the user asked for, so its
    // prompt stays away: no wallet spam.
    test('retrying the drives that failed asks again for those only', () async {
      allDrivesSyncAtOnce();
      final cubit = buildCubit();
      await settled();

      await cubit.retryFailedDrives(['failed-a', 'failed-b']);

      final ask = lastAsk();
      expect(ask.all, isFalse,
          reason: 'every cancelled prompt, failed or not, would come back');
      expect(ask.only, ['failed-a', 'failed-b']);
      expect(ask.only, isNot(contains('cancelled-not-failed')));
      await cubit.close();
    });

    test('and a sync the user starts with no drives named still asks for all',
        () async {
      allDrivesSyncAtOnce();
      final cubit = buildCubit();
      await settled();

      await cubit.startSync(onlyDriveIds: ['a', 'b']);

      final ask = lastAsk();
      expect(ask.all, isTrue);
      expect(ask.only, isNull);
      await cubit.close();
    });
  });

  /// The drive picker says why a sync did not start, so each refusal has its
  /// own reason and a sync that ran has none.
  group('why a single-drive sync was refused', () {
    tearDown(() => PublicationMode.debugSet(null));

    test('another sync is running', () async {
      final finish = aSingleDriveSyncThatHangs();
      final cubit = buildCubit();
      await settled();

      final first = cubit.startSyncForDrive(driveId: 'drive-a');
      await Future<void>.delayed(Duration.zero);
      expect(await cubit.startSyncForDrive(driveId: 'drive-b'), isFalse);
      expect(cubit.lastSingleSyncRefusal, SyncRefusal.anotherSync);

      finish.complete();
      await first;
      expect(await cubit.startSyncForDrive(driveId: 'drive-b'), isTrue);
      expect(cubit.lastSingleSyncRefusal, isNull,
          reason: 'a sync that ran was not refused, whatever came before');
      await cubit.close();
    });

    test('publication mode', () async {
      final cubit = buildCubit();
      await settled();
      PublicationMode.debugSet('publication.json');

      expect(await cubit.startSyncForDrive(driveId: 'drive-a'), isFalse);
      expect(cubit.lastSingleSyncRefusal, SyncRefusal.publicationMode);
      await cubit.close();
    });

    test('an ArConnect tab without focus', () async {
      when(() => profileCubit.isCurrentProfileArConnect())
          .thenAnswer((_) async => true);
      when(() => tabVisibility.isTabFocused()).thenReturn(false);
      final cubit = buildCubit();
      await settled();

      expect(await cubit.startSyncForDrive(driveId: 'drive-a'), isFalse);
      expect(cubit.lastSingleSyncRefusal, SyncRefusal.tabHidden);
      await cubit.close();
    });

    test('an activity that must not be interrupted', () async {
      when(() => activityCubit.state).thenReturn(ActivityInProgress());
      final cubit = buildCubit();
      await settled();

      expect(await cubit.startSyncForDrive(driveId: 'drive-a'), isFalse);
      expect(cubit.lastSingleSyncRefusal, SyncRefusal.activityInProgress);
      await cubit.close();
    });
  });
}
