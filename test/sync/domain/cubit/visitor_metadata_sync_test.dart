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
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

class _MockSyncRepository extends Mock implements SyncRepository {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class _MockActivityTracker extends Mock implements ActivityTracker {}

/// A visitor's explorer starts the sync of the drive they just opened as it
/// builds, and the cubit's own start-up path runs a metadata-only sync right
/// after. With no profile that path has nothing to do, and it used to say so
/// by emitting idle - over the sync that was running, so the explorer read
/// "no sync touches this drive" and flashed "Drive Not Synced" over files
/// that were seconds away.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';

  late MockProfileCubit profileCubit;
  late _MockActivityCubit activityCubit;
  late MockPromptToSnapshotBloc promptToSnapshotBloc;
  late MockTabVisibilitySingleton tabVisibility;
  late MockConfigService configService;
  late MockConfig config;
  late _MockActivityTracker activityTracker;
  late _MockSyncRepository syncRepository;
  late _MockUserPreferencesRepository userPreferencesRepository;

  /// Holds the single-drive sync open until a test lets it finish.
  late StreamController<SyncProgress> driveSync;

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
    driveSync = StreamController<SyncProgress>();

    // A visitor: no profile at all.
    when(() => profileCubit.state).thenReturn(ProfilePromptAdd());
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => profileCubit.refreshBalance()).thenAnswer((_) async {});
    when(() => activityCubit.state).thenReturn(ActivityNotRunning());
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenAnswer((_) => const Stream<void>.empty().listen((_) {}));
    when(() => configService.config).thenReturn(config);
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => userPreferencesRepository.load()).thenAnswer(
      (_) async => UserPreferences(
        currentTheme: ArDriveThemes.dark,
        lastSelectedDriveId: null,
        syncAllDrivesOnLogin: false,
      ),
    );
    when(() => syncRepository.hasPendingTransactions())
        .thenAnswer((_) async => false);
    when(() => syncRepository.probeDrivesWithChanges())
        .thenAnswer((_) async => const <String>{});
    when(() => syncRepository.syncSingleDrive(
          driveId: any(named: 'driveId'),
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer((_) => driveSync.stream);
  });

  // Not awaited: a controller nobody listened to only completes its close
  // once a listener has drained it, and the second test never listens.
  tearDown(() => unawaited(driveSync.close()));

  SyncCubit buildCubit() => SyncCubit(
        profileCubit: profileCubit,
        activityCubit: activityCubit,
        promptToSnapshotBloc: promptToSnapshotBloc,
        tabVisibility: tabVisibility,
        configService: configService,
        activityTracker: activityTracker,
        syncRepository: syncRepository,
        userPreferencesRepository: userPreferencesRepository,
      );

  test('a skipped metadata sync leaves a running single-drive sync alone',
      () async {
    final cubit = buildCubit();
    addTearDown(cubit.close);

    unawaited(cubit.startSyncForDrive(driveId: driveId));
    expect(cubit.state, isA<SyncInProgress>());
    expect(cubit.syncingDriveId, driveId);

    await cubit.syncMetadataOnly();

    expect(cubit.state, isA<SyncInProgress>(),
        reason: 'the explorer reads this to decide whether the drive it is '
            'opening is being written; idle here is the "Drive Not Synced" '
            'flash');
    expect(cubit.syncingDriveId, driveId);
  });

  test('a skipped metadata sync with nothing running still settles on idle',
      () async {
    // So nothing waiting on `waitCurrentSync()` hangs.
    final cubit = buildCubit();
    addTearDown(cubit.close);

    await cubit.syncMetadataOnly();

    expect(cubit.state, isA<SyncIdle>());
  });
}
