import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
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

/// A publication is exactly its snapshot (docs/PUBLICATIONS.md): whatever
/// asks, nothing syncs.
void main() {
  late _MockSyncRepository syncRepository;
  late MockProfileCubit profileCubit;
  late MockConfig config;
  SyncCubit? cubit;

  setUp(() {
    PublicationMode.debugSet('publication.json');
    syncRepository = _MockSyncRepository();
    profileCubit = MockProfileCubit();
    config = MockConfig();
    final configService = MockConfigService();
    final tabVisibility = MockTabVisibilitySingleton();

    when(() => profileCubit.state).thenReturn(ProfilePromptAdd());
    when(() => configService.config).thenReturn(config);
    when(() => config.autoSync).thenReturn(true);
    when(() => config.autoSyncIntervalInSeconds).thenReturn(1);
    when(() => tabVisibility.isTabFocused()).thenReturn(true);

    cubit = SyncCubit(
      profileCubit: profileCubit,
      activityCubit: _MockActivityCubit(),
      promptToSnapshotBloc: MockPromptToSnapshotBloc(),
      tabVisibility: tabVisibility,
      configService: configService,
      activityTracker: _MockActivityTracker(),
      syncRepository: syncRepository,
      userPreferencesRepository: _MockUserPreferencesRepository(),
    );
  });

  tearDown(() async {
    await cubit?.close();
    PublicationMode.debugSet(null);
  });

  test('starts idle, with nothing to wait for', () {
    expect(cubit!.state, isA<SyncIdle>());
  });

  test('never touches the sync repository, whatever asks', () async {
    final c = cubit!;

    expect(await c.startSync(), isFalse);
    expect(await c.startSync(deepSync: true), isFalse);
    expect(await c.startSyncForDrive(driveId: 'drive'), isFalse);
    await c.syncMetadataOnly();
    await c.checkForUnreadChanges();
    await c.arconnectSync();
    c.watchForPendingConfirmations();
    // Longer than the one-second auto-sync interval stubbed above.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    verifyZeroInteractions(syncRepository);
    expect(c.state, isA<SyncIdle>());
  });

  test('never asks for the profile or the tab to decide anything', () async {
    await cubit!.startSync();

    verifyNever(() => profileCubit.isCurrentProfileArConnect());
    verifyNever(() => profileCubit.logoutIfWalletMismatch());
  });
}
