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

  test('opening a drive nothing has walked fetches it', () async {
    await addDrive('never-walked');

    final cubit = await listing();
    cubit.syncDriveIfNeverSynced('never-walked');
    await cubit.close();

    final captured = verify(
      () => syncCubit.startSyncForDrive(
        driveId: captureAny(named: 'driveId'),
        deepSync: any(named: 'deepSync'),
        trigger: captureAny(named: 'trigger'),
      ),
    ).captured;

    expect(captured, ['never-walked', SyncTrigger.background],
        reason: 'opening an unwalked drive must fetch that drive, in the '
            'background - a scrim over the drive the user is walking into is '
            'the thing the background trigger exists to avoid');
  });

  test('opening a drive that has been walked fetches nothing', () async {
    await addDrive('walked', lastBlockHeight: 12345);

    final cubit = await listing();
    cubit.syncDriveIfNeverSynced('walked');
    await cubit.close();

    verifyNever(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        ));
  });

  test('a drive walked by a build that recorded only the time is left alone',
      () async {
    await addDrive('walked-once');

    final cubit = await listing(
      lastSynced: {'walked-once': DateTime(2026, 8, 1)},
    );
    cubit.syncDriveIfNeverSynced('walked-once');
    await cubit.close();

    verifyNever(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        ));
  });

  test('a sync already walking every drive is the fetch', () async {
    await addDrive('never-walked');

    // An all-drives sync names no drive, and covers all of them.
    when(() => syncCubit.syncingDriveId).thenReturn(null);

    final cubit = await listing(
      syncState: SyncInProgress(trigger: SyncTrigger.background),
    );
    cubit.syncDriveIfNeverSynced('never-walked');
    await cubit.close();

    verifyNever(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        ));
  });

  test('a sync walking a different drive does not stand in for this one',
      () async {
    await addDrive('never-walked');
    await addDrive('other', lastBlockHeight: 9);

    when(() => syncCubit.syncingDriveId).thenReturn('other');

    final cubit = await listing(
      syncState: SyncInProgress(trigger: SyncTrigger.background),
    );
    cubit.syncDriveIfNeverSynced('never-walked');
    await cubit.close();

    // The row's own `isSyncing` is false here, but so is it during an
    // all-drives sync for every row - which is why the decision is made off
    // the sync cubit rather than off the item a row was drawn with.
    final captured = verify(
      () => syncCubit.startSyncForDrive(
        driveId: captureAny(named: 'driveId'),
        deepSync: any(named: 'deepSync'),
        trigger: captureAny(named: 'trigger'),
      ),
    ).captured;

    expect(captured, ['never-walked', SyncTrigger.background]);
  });

  test('a drive the list does not hold starts nothing', () async {
    await addDrive('never-walked');

    final cubit = await listing();
    cubit.syncDriveIfNeverSynced('not-in-the-list');
    await cubit.close();

    verifyNever(() => syncCubit.startSyncForDrive(
          driveId: any(named: 'driveId'),
          deepSync: any(named: 'deepSync'),
          trigger: any(named: 'trigger'),
        ));
  });
}
