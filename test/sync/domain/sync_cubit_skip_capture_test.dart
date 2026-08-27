import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
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
///
/// The other way "no skips were reported" fails to mean "no skips happened"
/// is quieter, and needs no failure at all: a sync reports only about the
/// drives it opened, and it does not open all of them. The activity probe
/// sets aside every drive it believes unchanged, and those drives appear in
/// no list a completed report carries — not `failedDriveIds`, not the skip
/// map. What the cubit records is therefore per drive and not per sync, so
/// that a report's silence about a drive stays silence.
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
        examinedDriveIds: const {driveId},
        skippedEntityCount: 1,
        skippedEntityTxIdsByDrive: const {
          driveId: [skippedTxId],
        },
      );

  SyncProgress cleanReport() => SyncProgress.initial().copyWith(
        progress: 1,
        drivesCount: 1,
        drivesSynced: 1,
        examinedDriveIds: const {driveId},
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
      expect(cubit.lastSyncCoveredDriveIds, isEmpty);
      await cubit.close();
    });
  });

  /// The second hole in the precondition's inputs, and the one this group
  /// exists for.
  ///
  /// `syncAllDrives` probes for drive activity and sets aside the drives it
  /// believes unchanged. Those drives are not synced, and they are not added
  /// to `failedDriveIds` either — so a completed sweep used to leave them
  /// satisfying every check the publish precondition makes: a completion was
  /// stamped, the coverage claim did not exclude them, and the skip map had
  /// nothing to say about them. They read as **clean** off the back of a sync
  /// that never opened them.
  ///
  /// What a sync knows is what it examined. Everything here is about the
  /// difference between a report that is silent about a drive and a report
  /// that vouches for it.
  group('a drive the activity probe set aside', () {
    const probeSkippedDriveId = 'the-drive-nobody-looked-at';

    /// What `syncAllDrives` produces on the ordinary sweep where one drive
    /// changed and another did not: only the changed drive is examined, and
    /// nothing anywhere in the report names the other one.
    SyncProgress sweepThatExaminedOnly(String examined) =>
        SyncProgress.initial().copyWith(
          progress: 1,
          drivesCount: 1,
          drivesSynced: 1,
          examinedDriveIds: {examined},
        );

    test('is not vouched for by a sync that did not open it', () async {
      stubAllDrives(() => Stream.value(sweepThatExaminedOnly(driveId)));
      final cubit = buildCubit();

      await cubit.startSync();

      expect(
        cubit.lastSyncCompletedAt,
        isNotNull,
        reason: 'the sweep did finish - it is its silence about the other '
            'drive that must not be read as a verdict',
      );
      expect(cubit.lastSyncCoveredDriveIds, {driveId});
      expect(
        cubit.lastSyncCoveredDriveIds,
        isNot(contains(probeSkippedDriveId)),
        reason: 'the probe set this drive aside as unchanged, which is a '
            'claim about the chain and not about what any sync read',
      );
      await cubit.close();
    });

    test('keeps the skips of the last sync that did open it', () async {
      // The report a probe-skipped drive most needs to survive. Its skips are
      // old transactions the 240-block look-back no longer reaches, so the
      // probe finds no activity and every later sweep passes it by. If the
      // record went with the sweep that replaced it, a drive with a known gap
      // would go quiet and then read clean.
      stubAllDrives(() => Stream.value(SyncProgress.initial().copyWith(
            progress: 1,
            examinedDriveIds: const {probeSkippedDriveId},
            skippedEntityCount: 1,
            skippedEntityTxIdsByDrive: const {
              probeSkippedDriveId: [skippedTxId],
            },
          )));
      final cubit = buildCubit();
      await cubit.startSync();

      stubAllDrives(() => Stream.value(sweepThatExaminedOnly(driveId)));
      await cubit.startSync();

      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, {
        probeSkippedDriveId: [skippedTxId],
      });
      expect(cubit.lastSyncCoveredDriveIds, {probeSkippedDriveId, driveId});
      await cubit.close();
    });

    test('keeps a clean verdict across a sweep that passed it by', () async {
      // The other side of the same rule, and the reason "unknown" is not the
      // answer for every drive a sweep did not open: nothing synced this
      // drive, so neither its rows nor its watermark moved, and the last sync
      // that did read it is still describing it accurately.
      stubAllDrives(() => Stream.value(SyncProgress.initial().copyWith(
            progress: 1,
            examinedDriveIds: const {probeSkippedDriveId},
          )));
      final cubit = buildCubit();
      await cubit.startSync();

      stubAllDrives(() => Stream.value(sweepThatExaminedOnly(driveId)));
      await cubit.startSync();

      expect(cubit.lastSyncCoveredDriveIds, contains(probeSkippedDriveId));
      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, isEmpty);
      await cubit.close();
    });

    test('a sweep that examined nothing vouches for nothing', () async {
      // Every drive unchanged is the common case, not an edge one: the probe
      // finds no activity, `syncAllDrives` returns `emptySyncCompleted`, and
      // the sweep is a successful no-op. A successful no-op has still read
      // nothing.
      stubAllDrives(() => Stream.value(SyncProgress.emptySyncCompleted()));
      final cubit = buildCubit();

      await cubit.startSync();

      expect(cubit.lastSyncCoveredDriveIds, isEmpty);
      expect(cubit.lastSyncSkippedEntityTxIdsByDrive, isEmpty);
      await cubit.close();
    });
  });

  group('a drive a sync opened and then abandoned', () {
    test('loses the verdict an earlier sync gave it', () async {
      // The sync announces the drive, so it may have advanced its watermark
      // past entities it never read, and then dies before reporting. The
      // earlier "clean" describes a drive that no longer exists.
      stubAllDrives(() => Stream.value(cleanReport()));
      final cubit = buildCubit();
      await cubit.startSync();
      expect(cubit.lastSyncCoveredDriveIds, {driveId});

      stubAllDrives(() async* {
        yield SyncProgress.initial().copyWith(
          drivesCount: 1,
          examinedDriveIds: const {driveId},
        );
        throw Exception('the gateway went away mid-sync');
      });
      await cubit.startSync();

      expect(cubit.lastSyncCoveredDriveIds, isEmpty);
      await cubit.close();
    });

    test('loses it to a cancellation too', () async {
      stubAllDrives(() => Stream.value(cleanReport()));
      final cubit = buildCubit();
      await cubit.startSync();

      stubAllDrives(() async* {
        yield SyncProgress.initial().copyWith(
          drivesCount: 1,
          examinedDriveIds: const {driveId},
        );
        throw SyncCancelledException();
      });
      await cubit.startSync();

      expect(cubit.state, isA<SyncCancelled>());
      expect(cubit.lastSyncCoveredDriveIds, isEmpty);
      await cubit.close();
    });

    test('loses it when the sync ran to the end and failed the drive',
        () async {
      stubAllDrives(() => Stream.value(cleanReport()));
      final cubit = buildCubit();
      await cubit.startSync();

      stubAllDrives(() => Stream.value(SyncProgress.initial().copyWith(
            progress: 1,
            drivesCount: 1,
            drivesSynced: 1,
            examinedDriveIds: const {driveId},
            failedQueries: 1,
            failedDriveIds: const [driveId],
          )));
      await cubit.startSync();

      expect(cubit.state, isA<SyncCompleteWithErrors>());
      expect(
        cubit.lastSyncCoveredDriveIds,
        isEmpty,
        reason: 'a drive whose sync threw part-way may have been left with an '
            'advanced watermark and no report, so what an earlier sync said '
            'about it no longer holds',
      );
      await cubit.close();
    });

    test('loses it to a cancelled single-drive sync too', () async {
      stubSingleDrive(() => Stream.value(cleanReport()));
      final cubit = buildCubit();
      await cubit.startSyncForDrive(driveId: driveId);
      expect(cubit.lastSyncCoveredDriveIds, {driveId});

      stubSingleDrive(() async* {
        yield SyncProgress.initial().copyWith(
          isSingleDriveSync: true,
          drivesCount: 1,
          examinedDriveIds: const {driveId},
        );
        throw SyncCancelledException();
      });
      await cubit.startSyncForDrive(driveId: driveId);

      expect(cubit.lastSyncCoveredDriveIds, isEmpty);
      await cubit.close();
    });

    test('a drive the abandoned sync never opened keeps its verdict', () async {
      const otherDriveId = 'a-drive-this-sweep-passed-by';

      stubAllDrives(() => Stream.value(SyncProgress.initial().copyWith(
            progress: 1,
            examinedDriveIds: const {driveId, otherDriveId},
          )));
      final cubit = buildCubit();
      await cubit.startSync();

      stubAllDrives(() async* {
        yield SyncProgress.initial().copyWith(
          drivesCount: 1,
          examinedDriveIds: const {driveId},
        );
        throw Exception('the gateway went away mid-sync');
      });
      await cubit.startSync();

      expect(cubit.lastSyncCoveredDriveIds, {otherDriveId});
      await cubit.close();
    });
  });

  /// The precondition itself, read through the cubit rather than through the
  /// hand-built inputs `drive_state_sync_skip_status_test.dart` uses. That
  /// file proves the decision is right given honest inputs; this one proves
  /// the inputs are honest.
  group('what the publish precondition makes of it', () {
    DriveStateSyncSkipStatus statusFor(SyncCubit cubit, String id) =>
        SyncCubitDriveStateSkipSource(cubit).statusFor(id);

    test('refuses a drive the probe set aside', () async {
      const probeSkippedDriveId = 'the-drive-nobody-looked-at';

      stubAllDrives(() => Stream.value(SyncProgress.initial().copyWith(
            progress: 1,
            drivesCount: 1,
            drivesSynced: 1,
            examinedDriveIds: const {driveId},
          )));
      final cubit = buildCubit();

      await cubit.startSync();

      expect(
        statusFor(cubit, probeSkippedDriveId).state,
        DriveStateSyncSkipState.unknown,
        reason: 'publishing here would record a gap permanently on Arweave on '
            'the strength of a sync that never opened the drive',
      );
      expect(statusFor(cubit, driveId).isClean, isTrue);
      await cubit.close();
    });

    test('refuses a drive whose skips an unrelated sweep did not clear',
        () async {
      const otherDriveId = 'a-drive-this-sweep-did-open';

      stubAllDrives(() => Stream.value(reportWithSkips()));
      final cubit = buildCubit();
      await cubit.startSync();

      stubAllDrives(() => Stream.value(SyncProgress.initial().copyWith(
            progress: 1,
            drivesCount: 1,
            drivesSynced: 1,
            examinedDriveIds: const {otherDriveId},
          )));
      await cubit.startSync();

      final status = statusFor(cubit, driveId);
      expect(status.state, DriveStateSyncSkipState.skipped);
      expect(status.skippedEntityCount, 1);
      await cubit.close();
    });
  });
}
