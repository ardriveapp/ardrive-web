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

/// What the page is allowed to say about each drive, decided here.
///
/// The rule the whole page turns on lives in this cubit: a number read off the
/// local tables describes this device, and for a drive nothing has walked that
/// number is zero for a reason that has nothing to do with the drive. So it is
/// withheld rather than published.
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
  });

  tearDown(() async => db.close());

  Future<void> addDrive(
    String id, {
    String? name,
    int lastBlockHeight = 0,
    String owner = 'me',
    String privacy = DrivePrivacyTag.public,
  }) =>
      db.into(db.drives).insert(
            DrivesCompanion.insert(
              id: id,
              rootFolderId: '$id-root',
              ownerAddress: owner,
              name: name ?? id,
              privacy: privacy,
              lastBlockHeight: Value(lastBlockHeight),
            ),
          );

  Future<void> addFile(String driveId, String fileId, int size) =>
      db.into(db.fileEntries).insert(
            FileEntriesCompanion.insert(
              id: fileId,
              driveId: driveId,
              parentFolderId: '$driveId-root',
              name: fileId,
              dataTxId: '$fileId-tx',
              size: size,
              lastModifiedDate: DateTime(2024, 1, 1),
              path: '',
            ),
          );

  Future<List<Drive>> drivesNamed(List<String> ids) async {
    final all = await db.driveDao.allDrives().get();

    return ids.map((id) => all.firstWhere((d) => d.id == id)).toList();
  }

  DrivesListCubit buildCubit() => DrivesListCubit(
        drivesCubit: drivesCubit,
        syncCubit: syncCubit,
        driveDao: db.driveDao,
        userPreferencesRepository: preferences,
      );

  /// The state the cubit settles on for the given drives state.
  Future<DrivesListState> settle(
    DrivesState drivesState, {
    SyncState syncState = const _Idle(),
  }) async {
    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: drivesState);
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: syncState);

    final cubit = buildCubit();
    // The cubit reads the database before it can answer.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final state = cubit.state;
    await cubit.close();

    return state;
  }

  /// Like [settle], but hands back the live cubit so selection - which is
  /// several calls, not one - can actually be exercised.
  Future<DrivesListCubit> settleLive(
    DrivesState drivesState, {
    SyncState syncState = const _Idle(),
  }) async {
    whenListen(drivesCubit, const Stream<DrivesState>.empty(),
        initialState: drivesState);
    whenListen(syncCubit, const Stream<SyncState>.empty(),
        initialState: syncState);

    final cubit = buildCubit();
    addTearDown(cubit.close);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    return cubit;
  }

  DrivesLoadSuccess loaded(List<Drive> userDrives,
          {List<Drive> shared = const []}) =>
      DrivesLoadSuccess(
        selectedDriveId: userDrives.isEmpty ? null : userDrives.first.id,
        userDrives: userDrives,
        sharedDrives: shared,
        drivesWithAlerts: const [],
        canCreateNewDrive: true,
      );

  group('the four answers', () {
    test('a drives cubit that has not answered is still loading', () async {
      expect(await settle(DrivesLoadInProgress()), isA<DrivesListLoading>());
    });

    test('an account with no drives is empty, once we know it', () async {
      expect(
        await settle(DrivesLoadedWithNoDrivesFound(canCreateNewDrive: true)),
        isA<DrivesListEmpty>(),
      );
    });

    test('a drive list that could not be read is not an empty account',
        () async {
      when(() => syncCubit.driveListRefreshFailed).thenReturn(true);

      expect(
        await settle(DrivesLoadedWithNoDrivesFound(canCreateNewDrive: true)),
        isA<DrivesListUnavailable>(),
      );
    });

    test('drives are a list', () async {
      await addDrive('drive-a');

      final state = await settle(loaded(await drivesNamed(['drive-a'])));

      expect(state, isA<DrivesListLoaded>());
      expect((state as DrivesListLoaded).drives.single.id, 'drive-a');
    });
  });

  group('what each row is told', () {
    test('a walked drive publishes its count and its size', () async {
      await addDrive('drive-a', lastBlockHeight: 100);
      await addFile('drive-a', 'f1', 200);
      await addFile('drive-a', 'f2', 150);

      final state = await settle(loaded(await drivesNamed(['drive-a'])))
          as DrivesListLoaded;

      expect(state.drives.single.fileCount, 2);
      expect(state.drives.single.totalSize, 350);
      expect(state.drives.single.hasBeenWalked, isTrue);
    });

    test('a drive nothing has walked publishes neither', () async {
      await addDrive('drive-a');

      final state = await settle(loaded(await drivesNamed(['drive-a'])))
          as DrivesListLoaded;

      // Zero rows is what the table holds; it is not what the drive holds.
      expect(state.drives.single.hasBeenWalked, isFalse);
      expect(state.drives.single.fileCount, isNull);
      expect(state.drives.single.totalSize, isNull);
    });

    test('a recorded sync counts as having walked it, block height or not',
        () async {
      await addDrive('drive-a');
      when(() => preferences.currentPreferences).thenReturn(
        prefs(lastSynced: {'drive-a': DateTime(2026, 8, 1)}),
      );

      final state = await settle(loaded(await drivesNamed(['drive-a'])))
          as DrivesListLoaded;

      // A sync that ran and found nothing is a finding: no items, zero bytes.
      expect(state.drives.single.hasBeenWalked, isTrue);
      expect(state.drives.single.fileCount, 0);
      expect(state.drives.single.lastSyncedAt, DateTime(2026, 8, 1));
    });

    test('a drive somebody else owns is marked, not filed separately',
        () async {
      await addDrive('mine');
      await addDrive('theirs', owner: 'someone-else');

      final state = await settle(
        loaded(
          await drivesNamed(['mine']),
          shared: await drivesNamed(['theirs']),
        ),
      ) as DrivesListLoaded;

      expect(state.drives.map((d) => d.id), ['mine', 'theirs']);
      expect(
        state.drives.firstWhere((d) => d.id == 'theirs').isSharedWithMe,
        isTrue,
      );
      expect(
        state.drives.firstWhere((d) => d.id == 'mine').isSharedWithMe,
        isFalse,
      );
    });

    test('privacy comes off the drive itself', () async {
      await addDrive('drive-a', privacy: DrivePrivacyTag.private);

      final state = await settle(loaded(await drivesNamed(['drive-a'])))
          as DrivesListLoaded;

      expect(state.drives.single.isPrivate, isTrue);
    });

    test('a running sync of everything covers every row', () async {
      await addDrive('drive-a');
      await addDrive('drive-b');

      final state = await settle(
        loaded(await drivesNamed(['drive-a', 'drive-b'])),
        syncState: SyncInProgress(),
      ) as DrivesListLoaded;

      expect(state.drives.every((d) => d.isSyncing), isTrue);
    });

    test('a running sync of one drive covers only that row', () async {
      await addDrive('drive-a');
      await addDrive('drive-b');
      when(() => syncCubit.syncingDriveId).thenReturn('drive-a');

      final state = await settle(
        loaded(await drivesNamed(['drive-a', 'drive-b'])),
        syncState: SyncInProgress(),
      ) as DrivesListLoaded;

      expect(
        state.drives.firstWhere((d) => d.id == 'drive-a').isSyncing,
        isTrue,
      );
      expect(
        state.drives.firstWhere((d) => d.id == 'drive-b').isSyncing,
        isFalse,
      );
    });
  });

  /// Tapping Try Again is this page asking again, and while it is asking it
  /// knows nothing new.
  ///
  /// `syncMetadataOnly` emits `SyncLoadingDrives` *before* it makes its
  /// request. That wakes this cubit, and with an empty local table the answer
  /// it reached for was "this account has no drives" - so the retry painted
  /// "Getting Started" over the whole retry, which is the exact claim the page
  /// beneath this one exists to prevent.
  group('trying again', () {
    late StreamController<DrivesState> drivesStates;
    late StreamController<SyncState> syncStates;
    late Completer<void> requestFinished;

    /// The failure a login lands in when the gateway will not answer.
    DrivesListCubit buildAfterAFailedLoad() {
      drivesStates = StreamController<DrivesState>.broadcast();
      syncStates = StreamController<SyncState>.broadcast();

      whenListen(
        drivesCubit,
        drivesStates.stream,
        initialState: DrivesLoadedWithNoDrivesFound(canCreateNewDrive: true),
      );
      whenListen(
        syncCubit,
        syncStates.stream,
        initialState: SyncFailure(error: 'the gateway would not answer'),
      );
      // What the real getter is, rather than a fixed answer: `state is
      // SyncFailure`. A stub that stayed `true` through the retry would hide
      // the bug behind the failure state.
      when(() => syncCubit.driveListRefreshFailed)
          .thenAnswer((_) => syncCubit.state is SyncFailure);

      addTearDown(() async {
        await drivesStates.close();
        await syncStates.close();
      });

      return buildCubit();
    }

    /// The retry, stopped in the middle of its request.
    ///
    /// Faithful in the one respect that matters: the state that says "loading
    /// drives" is emitted before the request, not after it.
    void stubRetry({required bool findsDrives, bool fails = false}) {
      requestFinished = Completer<void>();

      when(() => syncCubit.syncMetadataOnly()).thenAnswer((_) async {
        syncStates.add(SyncLoadingDrives());

        await requestFinished.future;

        if (fails) {
          syncStates.add(SyncFailure(error: 'still no answer'));
          return;
        }

        if (findsDrives) {
          await addDrive('drive-a');
        }

        syncStates.add(SyncIdle());
      });
    }

    test('never says the account is empty while the retry is running',
        () async {
      final cubit = buildAfterAFailedLoad();
      final seen = <DrivesListState>[];
      final subscription = cubit.stream.listen(seen.add);

      await pumpEventQueue();
      // The page really did reach the failure - without this the rest of the
      // test would be asserting about nothing.
      expect(cubit.state, isA<DrivesListUnavailable>());

      stubRetry(findsDrives: true);
      final retry = cubit.retryLoadingDrives();

      // The whole length of the request, with the drive table still empty.
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesListLoading>());
      expect(
        seen.whereType<DrivesListEmpty>(),
        isEmpty,
        reason: 'the retry told the user they have no drives',
      );

      requestFinished.complete();
      await retry;
      await pumpEventQueue();

      // And still not while the drives cubit catches up with the table the
      // retry has just written.
      expect(
        seen.whereType<DrivesListEmpty>(),
        isEmpty,
        reason: 'emptiness was published between the write and the watch',
      );

      drivesStates.add(loaded(await drivesNamed(['drive-a'])));
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesListLoaded>());
      expect((cubit.state as DrivesListLoaded).drives.single.id, 'drive-a');
      expect(
        seen.whereType<DrivesListEmpty>(),
        isEmpty,
        reason: 'the retry told the user they have no drives',
      );

      await subscription.cancel();
      await cubit.close();
    });

    test('and does say so once the retry has looked and found nothing',
        () async {
      final cubit = buildAfterAFailedLoad();

      await pumpEventQueue();
      expect(cubit.state, isA<DrivesListUnavailable>());

      stubRetry(findsDrives: false);
      final retry = cubit.retryLoadingDrives();
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesListLoading>());

      requestFinished.complete();
      await retry;
      await pumpEventQueue();

      // The guard withholds the answer; it does not withhold it forever.
      expect(cubit.state, isA<DrivesListEmpty>());

      await cubit.close();
    });

    test('a retry that fails again is a failure, not an empty account',
        () async {
      final cubit = buildAfterAFailedLoad();

      await pumpEventQueue();

      stubRetry(findsDrives: false, fails: true);
      final retry = cubit.retryLoadingDrives();
      await pumpEventQueue();

      requestFinished.complete();
      await retry;
      await pumpEventQueue();

      expect(cubit.state, isA<DrivesListUnavailable>());

      await cubit.close();
    });
  });

  group('the one offer the page makes', () {
    test('stands while nothing has ever been walked', () async {
      await addDrive('drive-a');
      await addDrive('drive-b');

      final state =
          await settle(loaded(await drivesNamed(['drive-a', 'drive-b'])))
              as DrivesListLoaded;

      expect(state.nothingHasEverBeenSynced, isTrue);
    });

    test('is withdrawn as soon as one drive has been', () async {
      await addDrive('drive-a', lastBlockHeight: 10);
      await addDrive('drive-b');

      final state =
          await settle(loaded(await drivesNamed(['drive-a', 'drive-b'])))
              as DrivesListLoaded;

      expect(state.nothingHasEverBeenSynced, isFalse);
    });
  });

  /// Choosing drives to sync, and the one way a selection must never be lost.
  group('selecting drives to sync', () {
    setUp(() {
      when(() => syncCubit.syncDrives(any())).thenAnswer((_) async => true);
    });

    test('ticks accumulate and reach the sync as one run', () async {
      await addDrive('a');
      await addDrive('b');
      final cubit = await settleLive(loaded(await drivesNamed(['a', 'b'])));

      cubit.toggleSelected('a');
      cubit.toggleSelected('b');

      expect((cubit.state as DrivesListLoaded).selected, {'a', 'b'});

      cubit.syncSelectedDrives();
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => syncCubit.syncDrives(captureAny()))
          .captured
          .single as List<String>;
      expect(captured, containsAll(<String>['a', 'b']));
      expect(captured, hasLength(2),
          reason: 'four drives chosen is one run over four, not four runs');
    });

    test('a second tick unticks', () async {
      await addDrive('a');
      final cubit = await settleLive(loaded(await drivesNamed(['a'])));

      cubit.toggleSelected('a');
      cubit.toggleSelected('a');

      expect((cubit.state as DrivesListLoaded).selected, isEmpty);
    });

    test('nothing ticked syncs everything, rather than nothing', () async {
      when(() => syncCubit.startSync()).thenAnswer((_) async => true);

      await addDrive('a');
      final cubit = await settleLive(loaded(await drivesNamed(['a'])));

      cubit.syncSelectedDrives();
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => syncCubit.syncDrives(any()));
      verify(() => syncCubit.startSync()).called(1);
    });

    test('a run that started takes the selection away', () async {
      await addDrive('a');
      final cubit = await settleLive(loaded(await drivesNamed(['a'])));

      cubit.toggleSelected('a');
      cubit.syncSelectedDrives();
      await Future<void>.delayed(Duration.zero);

      expect((cubit.state as DrivesListLoaded).selected, isEmpty);
    });

    /// A sync is refused outright while another is running - one at a time,
    /// never queued. Clearing anyway would make the reader find and re-tick
    /// the same drives to try again.
    test('a run that was refused leaves it alone', () async {
      when(() => syncCubit.syncDrives(any())).thenAnswer((_) async => false);

      await addDrive('a');
      await addDrive('b');
      final cubit = await settleLive(loaded(await drivesNamed(['a', 'b'])));

      cubit.toggleSelected('a');
      cubit.toggleSelected('b');
      cubit.syncSelectedDrives();
      await Future<void>.delayed(Duration.zero);

      expect(
        (cubit.state as DrivesListLoaded).selected,
        {'a', 'b'},
        reason: 'the press did nothing, so it must not also cost the reader '
            'the selection they made',
      );
    });
  });
}

/// A sync doing nothing, which is what every test here starts from.
class _Idle implements SyncState {
  const _Idle();

  @override
  bool get isSuccessfulCompletion => false;

  @override
  List<Object> get props => const [];

  @override
  bool? get stringify => false;
}
