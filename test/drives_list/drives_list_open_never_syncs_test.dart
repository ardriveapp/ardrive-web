import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/drives_list/presentation/drives_list_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

class _MockSyncCubit extends MockCubit<SyncState> implements SyncCubit {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _Idle implements SyncState {
  const _Idle();

  @override
  bool get isSuccessfulCompletion => false;

  @override
  List<Object> get props => const [];

  @override
  bool? get stringify => false;
}

/// Choosing a drive is the act that fetches it.
///
/// The page is a list of drives nothing has necessarily looked at. Opening one
/// of those used only to navigate, so the first thing a new user saw inside
/// the drive they had just chosen was "Drive Not Synced" and a button asking
/// them to choose it again. Nothing in the widget tree proved otherwise, which
/// is why this file exists.
void main() {
  late Database db;
  late MockDrivesCubit drivesCubit;
  late _MockSyncCubit syncCubit;
  late _MockUserPreferencesRepository preferences;

  UserPreferences prefs({Map<String, DateTime> lastSynced = const {}}) =>
      UserPreferences(
        currentTheme: ArDriveThemes.dark,
        lastSelectedDriveId: null,
        driveLastSyncedAt: lastSynced,
      );

  setUpAll(() {
    // mocktail needs a real SyncTrigger before `any(named: 'trigger')` can
    // stand in for one.
    registerFallbackValue(SyncTrigger.background);
  });

  setUp(() {
    db = getTestDb();
    drivesCubit = MockDrivesCubit();
    syncCubit = _MockSyncCubit();
    preferences = _MockUserPreferencesRepository();

    when(() => syncCubit.driveListRefreshFailed).thenReturn(false);
    when(() => syncCubit.syncingDriveId).thenReturn(null);
    // The run's own scope and what it has finished, read by every surface
    // that tells a drive in the run from one beside it. Null scope is
    // "every drive"; nothing finished yet.
    when(() => syncCubit.syncingDriveIds).thenReturn(null);
    when(() => syncCubit.completedDriveIds).thenReturn(const []);
    when(() => preferences.currentPreferences).thenReturn(prefs());
    when(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        )).thenAnswer((_) async => true);
  });

  tearDown(() async => db.close());

  Future<void> addDrive(String id, {int lastBlockHeight = 0}) =>
      db.into(db.drives).insert(
            DrivesCompanion.insert(
              id: id,
              rootFolderId: '$id-root',
              ownerAddress: 'me',
              name: id,
              privacy: DrivePrivacyTag.public,
              lastBlockHeight: Value(lastBlockHeight),
            ),
          );

  DrivesLoadSuccess loaded(List<Drive> userDrives) => DrivesLoadSuccess(
        selectedDriveId: userDrives.isEmpty ? null : userDrives.first.id,
        userDrives: userDrives,
        sharedDrives: const [],
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      );

  /// A cubit that has settled on the drives currently in the database.
  Future<DrivesListCubit> listing({
    SyncState syncState = const _Idle(),
    Map<String, DateTime> lastSynced = const {},
  }) async {
    when(() => preferences.currentPreferences)
        .thenReturn(prefs(lastSynced: lastSynced));

    final drives = await db.driveDao.allDrives().get();

    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: loaded(drives));
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: syncState);

    final cubit = DrivesListCubit(
      drivesCubit: drivesCubit,
      syncCubit: syncCubit,
      driveDao: db.driveDao,
      userPreferencesRepository: preferences,
    );

    // The cubit reads the database before it can answer.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(cubit.state, isA<DrivesListLoaded>(),
        reason: 'the fixture never reached the state the tap acts on');

    return cubit;
  }

  test('a drive that has never been walked is listed, and never fetched',
      () async {
    // The whole point. Opening used to fetch on the way in, from either
    // surface, so a tap in the left nav quietly began minutes of network work
    // - the opposite of the sync-only-when-asked rule the rest of this stack
    // follows. A tap is a request to look at something.
    await addDrive('never-walked');

    final cubit = await listing();
    addTearDown(cubit.close);

    final state = cubit.state as DrivesListLoaded;
    expect(state.drives.single.hasBeenWalked, isFalse,
        reason: 'the fixture has to be a drive nothing has looked at');

    verifyNever(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        ));
    verifyNever(() => syncCubit.startSync(
          deepSync: any(named: 'deepSync'),
          skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck'),
          onlyDriveIds: any(named: 'onlyDriveIds'),
          trigger: any(named: 'trigger'),
        ));
  });
}
