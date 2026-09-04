import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/utils.dart';

class MockActivityTracker extends Mock implements ActivityTracker {}

class MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

void main() {
  late Database db;
  late DriveDao driveDao;
  late MockProfileCubit profileCubit;
  late MockPromptToSnapshotBloc promptToSnapshotBloc;
  late MockUserPreferencesRepository userPreferencesRepository;
  late MockArDriveAuth auth;
  late MockSyncBloc syncCubit;
  late StreamController<SyncState> syncStates;

  const ownerAddress = 'address';

  Future<void> insertDrive(String id) async {
    await db.into(db.drives).insert(
          DrivesCompanion.insert(
            id: id,
            name: id,
            ownerAddress: ownerAddress,
            rootFolderId: '$id-root',
            privacy: DrivePrivacyTag.public,
          ),
        );
  }

  DrivesCubit buildCubit() => DrivesCubit(
        activityTracker: MockActivityTracker(),
        auth: auth,
        profileCubit: profileCubit,
        driveDao: driveDao,
        promptToSnapshotBloc: promptToSnapshotBloc,
        userPreferencesRepository: userPreferencesRepository,
        syncCubit: syncCubit,
      );

  /// Holds the drive-list refresh open until the test says otherwise, the way
  /// a login sync holds it open while `updateUserDrives` is still running.
  Completer<void> holdRefreshOpen() {
    final gate = Completer<void>();
    when(() => syncCubit.waitForDriveListRefresh())
        .thenAnswer((_) => gate.future);
    return gate;
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();

    db = getTestDb();
    driveDao = db.driveDao;

    auth = MockArDriveAuth();
    when(() => auth.onAuthStateChanged())
        .thenAnswer((_) => const Stream<User?>.empty());
    when(() => auth.currentUser).thenReturn(fakeUserJson);

    profileCubit = MockProfileCubit();
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: fakeUserJson, useTurbo: false),
    );

    promptToSnapshotBloc = MockPromptToSnapshotBloc();

    userPreferencesRepository = MockUserPreferencesRepository();
    when(() => userPreferencesRepository.load()).thenAnswer(
      (_) async => const UserPreferences(
        currentTheme: ArDriveThemes.dark,
        lastSelectedDriveId: null,
      ),
    );
    when(() => userPreferencesRepository.saveUserHasHiddenItem(any()))
        .thenAnswer((_) async {});
    when(() => userPreferencesRepository.saveLastSelectedDriveId(any()))
        .thenAnswer((_) async {});

    syncCubit = MockSyncBloc();
    syncStates = StreamController<SyncState>.broadcast();
    whenListen(syncCubit, syncStates.stream, initialState: SyncIdle());
    when(() => syncCubit.waitForDriveListRefresh()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await syncStates.close();
    await db.close();
  });

  test('HARNESS PROOF: reports the drives that are already in the table',
      () async {
    await insertDrive('drive-a');

    final cubit = buildCubit();
    final emitted = <DrivesState>[];
    final sub = cubit.stream.listen(emitted.add);

    await pumpEventQueue();

    expect(cubit.state, isA<DrivesLoadSuccess>());
    final state = cubit.state as DrivesLoadSuccess;
    expect(state.userDrives.map((d) => d.id), ['drive-a']);
    expect(emitted, isNotEmpty);

    await sub.cancel();
    await cubit.close();
  });

  group('an empty table before the drive list has been looked at', () {
    /// The bug, stated as a test: on a login with an empty local database the
    /// cubit announced "no drives" as a fact, and the sidebar, the router and
    /// the explorer all believed it - for the whole length of the fetch.
    test('says nothing at all while the refresh is still running', () async {
      holdRefreshOpen();

      final cubit = buildCubit();
      final emitted = <DrivesState>[];
      final sub = cubit.stream.listen(emitted.add);

      await pumpEventQueue();

      expect(
        emitted.whereType<DrivesLoadSuccess>(),
        isEmpty,
        reason: 'an unanswered drive list must not be reported as success',
      );
      expect(cubit.state, isA<DrivesLoadInProgress>());

      await sub.cancel();
      await cubit.close();
    });

    /// The other half of the same coin: a genuinely new user still has to be
    /// told, or the fix trades one wrong screen for a permanent blank one.
    test('reports the empty account once the refresh has finished', () async {
      final gate = holdRefreshOpen();

      final cubit = buildCubit();
      final emitted = <DrivesState>[];
      final sub = cubit.stream.listen(emitted.add);

      await pumpEventQueue();
      expect(emitted.whereType<DrivesLoadSuccess>(), isEmpty);

      gate.complete();
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesLoadSuccess>());
      expect((cubit.state as DrivesLoadSuccess).hasNoDrives, isTrue);

      await sub.cancel();
      await cubit.close();
    });

    /// The case the whole change exists for: the refresh found drives. What
    /// the user must never see is "none found" landing on top of them.
    test('reports the drives the refresh wrote, not "none found"', () async {
      final gate = holdRefreshOpen();

      final cubit = buildCubit();
      final emitted = <DrivesState>[];
      final sub = cubit.stream.listen(emitted.add);

      await pumpEventQueue();

      await insertDrive('drive-a');
      gate.complete();
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesLoadSuccess>());
      final state = cubit.state as DrivesLoadSuccess;
      expect(state.userDrives.map((d) => d.id), ['drive-a']);
      expect(
        emitted.whereType<DrivesLoadSuccess>().where((s) => s.hasNoDrives),
        isEmpty,
        reason: 'the stale empty snapshot must not be reported after the fact',
      );

      await sub.cancel();
      await cubit.close();
    });

    /// A wait nobody ends must not pin the sidebar shut for good.
    test('answers anyway when the refresh itself fails', () async {
      when(() => syncCubit.waitForDriveListRefresh())
          .thenAnswer((_) async => throw Exception('gateway said no'));

      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesLoadSuccess>());
      expect((cubit.state as DrivesLoadSuccess).hasNoDrives, isTrue);

      await cubit.close();
    });

    /// Closing mid-wait is the ordinary way this ends - the user logs out, or
    /// the route is torn down - and an emit after close throws.
    test('does not emit after being closed mid-wait', () async {
      final gate = holdRefreshOpen();

      final cubit = buildCubit();
      final emitted = <DrivesState>[];
      final sub = cubit.stream.listen(emitted.add);

      await pumpEventQueue();
      await cubit.close();

      gate.complete();
      await pumpEventQueue();

      expect(emitted.whereType<DrivesLoadSuccess>(), isEmpty);

      await sub.cancel();
    });

    /// The wait is opened once, however many times the watch fires.
    test('opens a single wait however often the watch re-fires', () async {
      final gate = holdRefreshOpen();

      final cubit = buildCubit();
      await pumpEventQueue();

      // A ghost folder is enough to re-fire the combined stream without
      // putting a drive in the table.
      await db.into(db.folderEntries).insert(
            FolderEntriesCompanion.insert(
              id: 'ghost-folder',
              driveId: 'drive-a',
              name: 'ghost',
              path: '',
              isGhost: const Value(true),
            ),
          );
      await pumpEventQueue();

      verify(() => syncCubit.waitForDriveListRefresh()).called(1);

      gate.complete();
      await cubit.close();
    });
  });

  /// Choosing a drive has to reach a surface that is not the explorer.
  ///
  /// On the drives list the selected drive is not what is on screen - the list
  /// is - so a sidebar tap changed a field nothing was drawing. The selection
  /// is announced so a page that navigates can hear it, and only selections a
  /// person made are announced: the pick this cubit makes for itself when the
  /// list first loads does not go through [DrivesCubit.selectDrive].
  group('announcing a chosen drive', () {
    test('a selection is announced', () async {
      await insertDrive('drive-a');
      await insertDrive('drive-b');

      final cubit = buildCubit();
      await pumpEventQueue();

      final announced = <String>[];
      final subscription = cubit.driveSelections.listen(announced.add);

      cubit.selectDrive('drive-b');
      await pumpEventQueue();

      expect(announced, ['drive-b']);

      await subscription.cancel();
      await cubit.close();
    });

    test('choosing the drive that is already selected is still a choice',
        () async {
      await insertDrive('drive-a');

      final cubit = buildCubit();
      await pumpEventQueue();

      // It selects one on its own as the list loads, and re-selecting it emits
      // no new state - which is exactly why the tap needs saying out loud.
      expect((cubit.state as DrivesLoadSuccess).selectedDriveId, 'drive-a');

      final announced = <String>[];
      final subscription = cubit.driveSelections.listen(announced.add);

      cubit.selectDrive('drive-a');
      await pumpEventQueue();

      expect(announced, ['drive-a']);

      await subscription.cancel();
      await cubit.close();
    });

    test('the drive it picks for itself is not announced', () async {
      await insertDrive('drive-a');

      final cubit = buildCubit();

      final announced = <String>[];
      final subscription = cubit.driveSelections.listen(announced.add);

      await pumpEventQueue();

      // A page that navigated on this would close itself before it was read.
      expect((cubit.state as DrivesLoadSuccess).selectedDriveId, 'drive-a');
      expect(announced, isEmpty);

      await subscription.cancel();
      await cubit.close();
    });
  });

  group('a returning user whose drives are already local', () {
    /// The common case, and the one that must not regress into a wait.
    test('never waits on the drive list refresh', () async {
      holdRefreshOpen();
      await insertDrive('drive-a');

      final cubit = buildCubit();
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesLoadSuccess>());
      expect((cubit.state as DrivesLoadSuccess).userDrives.map((d) => d.id),
          ['drive-a']);
      verifyNever(() => syncCubit.waitForDriveListRefresh());

      await cubit.close();
    });
  });
}
