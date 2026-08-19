import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart' show ArDriveThemes;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

/// What [SyncCubit] records about a sync, and — the point of this file — what
/// it must decline to record.
///
/// `lastSyncCompletedAt` and `lastSyncSkippedEntityTxIdsByDrive` are not
/// diagnostics. `driveStateSyncSkipStatus` reads them as the precondition on
/// publishing a drive state artifact, and an artifact records the gap it was
/// built over permanently and immutably on Arweave. So "a sync finished and
/// skipped nothing" has to mean a sync that finished.
///
/// Both entry points capture *after* their `catch`, which is the right place
/// for the state emission that follows and the wrong place for the capture: a
/// sync whose progress stream ended in an error arrives there too, having
/// produced no final report, and stamping a completion then claims a clean
/// sweep of work that stopped early.
class _MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class _MockActivityTracker extends Mock implements ActivityTracker {}

class _MockSyncRepository extends Mock implements SyncRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

void main() {
  const driveId = 'drive-id';
  const skippedTxId = 'the-one-that-got-away';

  late MockProfileCubit profileCubit;
  late _MockActivityCubit activityCubit;
  late MockPromptToSnapshotBloc promptToSnapshotBloc;
  late MockTabVisibilitySingleton tabVisibility;
  late MockConfigService configService;
  late _MockSyncRepository syncRepository;
  late _MockUserPreferencesRepository userPreferences;

  setUpAll(() {
    registerFallbackValue(const SyncRunning(isRunning: false));
  });

  SyncProgress reportWithSkips() => SyncProgress.initial().copyWith(
        progress: 1,
        drivesCount: 1,
        drivesSynced: 1,
        skippedEntityCount: 1,
        skippedEntityTxIdsByDrive: const {
          driveId: [skippedTxId],
        },
      );

  SyncProgress cleanReport() => SyncProgress.initial().copyWith(
        progress: 1,
        drivesCount: 1,
        drivesSynced: 1,
      );

  /// A cubit whose constructor does not start syncing on its own. Every stream
  /// it wires up in the constructor is stubbed to do nothing, so the only sync
  /// that runs is the one a test asks for.
  SyncCubit buildCubit() => SyncCubit(
        profileCubit: profileCubit,
        activityCubit: activityCubit,
        promptToSnapshotBloc: promptToSnapshotBloc,
        tabVisibility: tabVisibility,
        configService: configService,
        activityTracker: _MockActivityTracker(),
        syncRepository: syncRepository,
        userPreferencesRepository: userPreferences,
      );

  setUp(() {
    profileCubit = MockProfileCubit();
    activityCubit = _MockActivityCubit();
    promptToSnapshotBloc = MockPromptToSnapshotBloc();
    tabVisibility = MockTabVisibilitySingleton();
    configService = MockConfigService();
    syncRepository = _MockSyncRepository();
    userPreferences = _MockUserPreferencesRepository();

    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      // Far enough away that the periodic timer never fires during a test.
      autoSyncIntervalInSeconds: 60 * 60,
      autoSync: false,
    ));

    // Not logged in: no wallet work, no `updateUserDrives`, no balance refresh.
    // The capture under test does not depend on any of it.
    when(() => profileCubit.state).thenReturn(ProfilePromptLogIn());
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => activityCubit.state).thenReturn(ActivityNotRunning());
    when(() => promptToSnapshotBloc.add(any())).thenReturn(null);
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenReturn(const Stream<void>.empty().listen((_) {}));

    // `syncAllDrivesOnLogin: false` sends the constructor down
    // `syncMetadataOnly`, which for a logged-out profile is a no-op.
    when(() => userPreferences.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.light,
        lastSelectedDriveId: null,
        syncAllDrivesOnLogin: false,
      ),
    );

    when(() => syncRepository.numberOfFilesInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.numberOfFoldersInWallet())
        .thenAnswer((_) async => 0);
  });

  void stubAllDrives(Stream<SyncProgress> Function() progress) {
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => progress());
  }

  void stubSingleDrive(Stream<SyncProgress> Function() progress) {
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => progress());
  }

  group('a sync that reached its end', () {
    test('records what it skipped, and that it finished', () async {
      stubAllDrives(() => Stream.value(reportWithSkips()));
      final cubit = buildCubit();

      await cubit.startSync();

      expect(cubit.lastSyncCompletedAt, isNotNull);
      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, {
        driveId: [skippedTxId],
      });
      await cubit.close();
    });

    test('records a clean sweep as clean', () async {
      stubAllDrives(() => Stream.value(cleanReport()));
      final cubit = buildCubit();

      await cubit.startSync();

      expect(cubit.lastSyncCompletedAt, isNotNull);
      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, isEmpty);
      await cubit.close();
    });
  });

  group('a sync that did not', () {
    test('does not stamp a completion when the stream fails part-way',
        () async {
      // The failure this whole file is about. The stream carries a drive or
      // two, then errors — so the final progress, the one that reports what
      // was skipped, never arrives. Capturing here would record the *initial*
      // empty skip map as this sync's report and say a sync had finished.
      stubAllDrives(() async* {
        yield SyncProgress.initial().copyWith(drivesCount: 2, progress: 0.4);
        throw Exception('the gateway went away mid-sync');
      });
      final cubit = buildCubit();

      await cubit.startSync();

      expect(
        cubit.lastSyncCompletedAt,
        isNull,
        reason: 'no sync has finished in this session; a stamp here reads as '
            'one that finished and found nothing to skip',
      );
      await cubit.close();
    });

    test('leaves the previous completed sync\'s record alone', () async {
      // The stamp is not just about this sync. A failed sweep that replaced a
      // good report with an empty one would turn a drive that is known to have
      // skips into a drive that looks clean — which is worse than either.
      stubAllDrives(() => Stream.value(reportWithSkips()));
      final cubit = buildCubit();
      await cubit.startSync();

      final firstCompletion = cubit.lastSyncCompletedAt;
      expect(firstCompletion, isNotNull);

      stubAllDrives(() => Stream<SyncProgress>.error(Exception('nope')));
      await cubit.startSync();

      expect(cubit.lastSyncCompletedAt, firstCompletion);
      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, {
        driveId: [skippedTxId],
      });
      await cubit.close();
    });

    test('does not stamp a completion when the sync was cancelled', () async {
      stubAllDrives(
        () => Stream<SyncProgress>.error(SyncCancelledException()),
      );
      final cubit = buildCubit();

      await cubit.startSync();

      expect(cubit.state, isA<SyncCancelled>());
      expect(cubit.lastSyncCompletedAt, isNull);
      await cubit.close();
    });
  });

  group('the single-drive entry point', () {
    test('records a sync that reached its end', () async {
      stubSingleDrive(() => Stream.value(reportWithSkips()));
      final cubit = buildCubit();

      await cubit.startSyncForDrive(driveId: driveId);

      expect(cubit.lastSyncCompletedAt, isNotNull);
      expect(cubit.lastSyncCoveredDriveIds, {driveId});
      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, {
        driveId: [skippedTxId],
      });
      await cubit.close();
    });

    test('does not stamp a completion when the stream fails part-way',
        () async {
      // The same hole, in the entry point the drive detail page's "sync this
      // drive" reaches — and the one whose report the publish precondition is
      // most likely to be reading, because it is scoped to the very drive the
      // user is about to publish.
      stubSingleDrive(() async* {
        yield SyncProgress.initial().copyWith(
          isSingleDriveSync: true,
          drivesCount: 1,
        );
        throw Exception('the gateway went away mid-sync');
      });
      final cubit = buildCubit();

      await cubit.startSyncForDrive(driveId: driveId);

      expect(cubit.lastSyncCompletedAt, isNull);
      expect(cubit.lastSyncCoveredDriveIds, isNull);
      await cubit.close();
    });
  });
}
