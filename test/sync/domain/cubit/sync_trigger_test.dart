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

import '../../../test_utils/mocks.dart';

class MockSyncRepository extends Mock implements SyncRepository {}

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class MockActivityCubit extends MockCubit<ActivityState>
    implements ActivityCubit {}

class MockActivityTracker extends Mock implements ActivityTracker {}

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

    when(() => profileCubit.state).thenReturn(ProfileCheckingAvailability());
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => tabVisibility.isTabFocused()).thenReturn(true);
    when(() => tabVisibility.onTabGetsFocused(any()))
        .thenAnswer((_) => const Stream<void>.empty().listen((_) {}));
    when(() => configService.config).thenReturn(config);
    // Nothing here may fire a second sync of its own.
    when(() => config.autoSync).thenReturn(false);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(3600);
    when(() => syncRepository.syncAllDrives(
          wallet: any(named: 'wallet'),
          password: any(named: 'password'),
          cipherKey: any(named: 'cipherKey'),
          syncDeep: any(named: 'syncDeep'),
          driveIdsToRetry: any(named: 'driveIdsToRetry'),
          cancellationToken: any(named: 'cancellationToken'),
          txFechedCallback: any(named: 'txFechedCallback'),
        )).thenAnswer(
      (_) => Stream.value(SyncProgress.emptySyncCompleted()),
    );
    when(() => syncRepository.numberOfFilesInWallet())
        .thenAnswer((_) async => 0);
    when(() => syncRepository.numberOfFoldersInWallet())
        .thenAnswer((_) async => 0);
  });

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

  /// Every trigger the cubit reported, waiting for the sync to actually emit
  /// rather than for a fixed slice of wall clock - which a loaded CI box can
  /// spend without the sync ever starting, leaving nothing to assert on.
  Future<List<SyncTrigger>> triggersOf(
    SyncCubit cubit, {
    Future<void> Function()? act,
  }) async {
    final triggers = <SyncTrigger>[];
    final emitted = Completer<void>();

    final subscription = cubit.stream.listen((state) {
      if (state is SyncInProgress) {
        triggers.add(state.trigger);
        if (!emitted.isCompleted) {
          emitted.complete();
        }
      }
    });

    await act?.call();
    // A timeout returns what we have, so the expectation below fails with the
    // triggers it saw instead of hanging or throwing a bare StateError.
    await emitted.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {},
    );
    await subscription.cancel();

    return triggers;
  }

  test('the sync on login says nobody asked for it', () async {
    final cubit = buildCubit(syncAllDrivesOnLogin: true);

    final triggers = await triggersOf(cubit);
    await cubit.close();

    expect(triggers, [SyncTrigger.background]);
  });

  test('the periodic sync says nobody asked for it either', () async {
    // The timer's own path, wound down from an hour to a beat.
    when(() => config.autoSync).thenReturn(true);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(1);

    // Login starts nothing here, so the only sync that can emit is the one the
    // timer fires.
    final cubit = buildCubit(syncAllDrivesOnLogin: false);

    final triggers = await triggersOf(cubit);
    await cubit.close();

    expect(triggers, [SyncTrigger.background]);
  });

  test('a sync started from anywhere else is one the user asked for', () async {
    // Login only loads drive metadata here, so the resync below is the first
    // full sync and cannot be turned away for one already running.
    final cubit = buildCubit(syncAllDrivesOnLogin: false);

    final triggers = await triggersOf(
      cubit,
      act: () => cubit.startSync(),
    );
    await cubit.close();

    expect(triggers, [SyncTrigger.userInitiated]);
  });

  test('a retry is a sync the user asked for', () async {
    final cubit = buildCubit(syncAllDrivesOnLogin: false);

    final triggers = await triggersOf(
      cubit,
      act: () => cubit.retryFailedDrives(const ['drive-id']),
    );
    await cubit.close();

    expect(triggers, [SyncTrigger.userInitiated]);
  });
}
