import 'dart:async';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
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

class _MockSyncRepository extends Mock implements SyncRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _FakeWallet extends Fake implements Wallet {}

class _FakeSecretKey extends Fake implements SecretKey {}

/// A sync must not outlive the cubit, and a cancelled one must not be reported.
///
/// Both were unreachable until this stack. A running sync used to hold a
/// full-screen scrim over the whole app, Log Out included, so there was no way
/// to close [SyncCubit] with a sync in flight. The scrim is gone by design -
/// `SyncStrip` reports without taking the app, and it is an `IgnorePointer` -
/// so every control is live mid-sync and this is now an ordinary thing to do.
///
/// What is on the other side of it: `ArDriveAuth.logout()` empties every table
/// *before* the cubit closes, and `SyncRepository` is an app-level singleton
/// above the auth gate. An orphaned sync therefore spends the next few minutes
/// writing the previous wallet's drives and revisions back into the emptied
/// database, which `DrivesCubit` watches through an unfiltered `allDrives()`.
void main() {
  late MockProfileCubit profileCubit;
  late _MockActivityCubit activityCubit;
  late MockPromptToSnapshotBloc promptToSnapshotBloc;
  late MockTabVisibilitySingleton tabVisibility;
  late MockConfigService configService;
  late MockConfig config;
  late _MockActivityTracker activityTracker;
  late _MockSyncRepository syncRepository;
  late _MockUserPreferencesRepository userPreferencesRepository;

  /// The sync's next cancellation checkpoint, held open until a test releases
  /// it.
  ///
  /// A cancellation is never instantaneous: the repository notices at its next
  /// checkpoint, which in production is a network round trip away. That gap is
  /// the whole hazard, so it is made explicit here rather than raced with a
  /// delay - the cubit is closed strictly *before* the sync wakes up, every
  /// run.
  late Completer<void> nextCheckpoint;

  setUpAll(() {
    registerFallbackValue(false);
    registerFallbackValue(_FakeWallet());
    registerFallbackValue(_FakeSecretKey());
  });

  setUp(() {
    profileCubit = MockProfileCubit();
    activityCubit = _MockActivityCubit();
    promptToSnapshotBloc = MockPromptToSnapshotBloc();
    tabVisibility = MockTabVisibilitySingleton();
    configService = MockConfigService();
    config = MockConfig();
    activityTracker = _MockActivityTracker();
    syncRepository = _MockSyncRepository();
    userPreferencesRepository = _MockUserPreferencesRepository();

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
    // Nothing here may fire a sync of its own.
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

    nextCheckpoint = Completer<void>();
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

  /// Lets the cubit's own login path finish before a test starts a sync.
  Future<void> settled() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// A sync that keeps going until its token says otherwise, the way the real
  /// repository does.
  ///
  /// It yields before it checks, on purpose: there is always one more progress
  /// event after a cancellation is requested, and that event is what reaches a
  /// closed controller.
  Stream<SyncProgress> runsUntilCancelled(SyncCancellationToken? token) async* {
    while (true) {
      await nextCheckpoint.future;
      nextCheckpoint = Completer<void>();
      yield SyncProgress.initial();
      token?.checkCancellation();
    }
  }

  /// Captures the token the cubit hands the repository, so a test can ask
  /// whether the cubit actually cancelled it rather than inferring.
  late SyncCancellationToken? issuedToken;

  void aSingleDriveSyncThatRunsUntilCancelled() {
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((invocation) {
      issuedToken = invocation.namedArguments[#cancellationToken]
          as SyncCancellationToken?;
      return runsUntilCancelled(issuedToken);
    });
  }

  void anAllDrivesSyncThatRunsUntilCancelled() {
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((invocation) {
      issuedToken = invocation.namedArguments[#cancellationToken]
          as SyncCancellationToken?;
      return runsUntilCancelled(issuedToken);
    });
  }

  group('closing the cubit stops the sync', () {
    test('the running sync is cancelled, not abandoned', () async {
      aSingleDriveSyncThatRunsUntilCancelled();

      final cubit = buildCubit();
      await settled();

      final sync = cubit.startSyncForDrive(driveId: 'drive-a');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state, isA<SyncInProgress>(),
          reason: 'precondition: a sync is running');
      expect(issuedToken, isNotNull);
      expect(issuedToken!.isCancelled, isFalse);

      await cubit.close();

      expect(
        issuedToken!.isCancelled,
        isTrue,
        reason: 'a sync left running writes the previous wallet\'s drives '
            'into the database logout has just emptied',
      );

      // And it really does unwind, rather than being left to run.
      nextCheckpoint.complete();
      await sync.timeout(
        const Duration(seconds: 2),
        onTimeout: () => fail('the sync went on after the cubit was closed'),
      );
    });

    test('the sync unwinding afterwards emits nothing and publishes nothing',
        () async {
      // The cancellation is noticed at the repository's next checkpoint, so
      // everything after it - the terminal emit, the last progress event -
      // runs against a cubit and a controller that are already closed. Both
      // throw when that is not guarded, and the throw comes back out of this
      // future.
      aSingleDriveSyncThatRunsUntilCancelled();

      final cubit = buildCubit();
      await settled();

      final sync = cubit.startSyncForDrive(driveId: 'drive-a');
      await Future<void>.delayed(const Duration(milliseconds: 5));

      final lastStateBeforeClose = cubit.state;

      await cubit.close();

      expect(cubit.syncProgressController.isClosed, isTrue,
          reason: 'the controller is closed with the cubit that owns it');

      // Only now does the sync notice, which is the order production runs in.
      nextCheckpoint.complete();

      expect(
        await sync.timeout(const Duration(seconds: 2)),
        isFalse,
        reason: 'a cancelled sync started nothing the caller may report',
      );

      expect(cubit.state, same(lastStateBeforeClose),
          reason: 'nothing may be emitted after close');
    });

    test('an all-drives sync is stopped on the same terms', () async {
      anAllDrivesSyncThatRunsUntilCancelled();

      final cubit = buildCubit();
      await settled();

      final sync = cubit.startSync();
      await Future<void>.delayed(const Duration(milliseconds: 5));

      expect(cubit.state, isA<SyncInProgress>());

      await cubit.close();

      expect(issuedToken!.isCancelled, isTrue);

      nextCheckpoint.complete();
      expect(
        await sync.timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('the sync went on after the cubit was closed'),
        ),
        isFalse,
      );
    });
  });

  group('a cancelled sync answers the same either way', () {
    test('startSyncForDrive returns false, exactly as startSync does',
        () async {
      // They used to disagree, and the disagreement stranded the explorer:
      // `DriveDetailCubit.syncCurrentDrive` emits a loading state, takes
      // `true` for "a sync ran", then finds `SyncCancelled` and returns
      // without emitting - leaving "Opening Drive X" and a sweeping bar that
      // nothing ever clears.
      aSingleDriveSyncThatRunsUntilCancelled();

      final single = buildCubit();
      await settled();

      final singleSync = single.startSyncForDrive(driveId: 'drive-a');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      single.cancelSync();
      nextCheckpoint.complete();

      expect(await singleSync.timeout(const Duration(seconds: 2)), isFalse);
      expect(single.state, isA<SyncCancelled>(),
          reason: 'the cancellation is still reported by the state');
      await single.close();

      anAllDrivesSyncThatRunsUntilCancelled();
      nextCheckpoint = Completer<void>();

      final all = buildCubit();
      await settled();

      final allSync = all.startSync();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      all.cancelSync();
      nextCheckpoint.complete();

      expect(await allSync.timeout(const Duration(seconds: 2)), isFalse);
      await all.close();
    });
  });
}
