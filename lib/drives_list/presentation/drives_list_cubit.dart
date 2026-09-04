import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/drives_list/domain/drive_list_sort.dart';
import 'package:ardrive/drives_list/domain/drive_scope.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/compare_alphabetically_and_natural.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'drives_list_state.dart';

/// Assembles the drives list out of three local reads and nothing else.
///
/// It makes no network request of any kind. The drive list itself is already
/// in the local database - `updateUserDrives` is the one thing login fetches
/// unconditionally - and the two numbers per row come from the file table.
/// Everything this page shows is either already on the device or explicitly
/// withheld.
class DrivesListCubit extends Cubit<DrivesListState> {
  DrivesListCubit({
    required DrivesCubit drivesCubit,
    required SyncCubit syncCubit,
    required DriveDao driveDao,
    required UserPreferencesRepository userPreferencesRepository,
  })  : _drivesCubit = drivesCubit,
        _syncCubit = syncCubit,
        _driveDao = driveDao,
        _userPreferencesRepository = userPreferencesRepository,
        super(const DrivesListLoading()) {
    _subscription = Rx.combineLatest2<DrivesState, SyncState, void>(
      drivesCubit.stream.startWith(drivesCubit.state),
      syncCubit.stream.startWith(syncCubit.state),
      (_, __) {},
    ).listen((_) => unawaited(_refresh()));
  }

  final DrivesCubit _drivesCubit;
  final SyncCubit _syncCubit;
  final DriveDao _driveDao;
  final UserPreferencesRepository _userPreferencesRepository;

  late final StreamSubscription<void> _subscription;

  /// Which refresh is the current one.
  ///
  /// Both sources fire freely while a sync runs, and each refresh awaits the
  /// database - so two can be in flight at once and the slower one would
  /// otherwise land last and paint stale counts over fresh ones.
  int _sequence = 0;

  /// How many drive-list refreshes this page has started and is still waiting
  /// on.
  ///
  /// The one thing the page may never say is "you have no drives" about a look
  /// it has not finished taking - and its own Try Again is a look it takes.
  /// `syncMetadataOnly` emits `SyncLoadingDrives` *before* it makes the
  /// request, which wakes this cubit's subscription; with an empty table that
  /// landed on the empty state, so tapping Try Again painted "Getting Started"
  /// for the whole length of the retry.
  int _refreshesWeStarted = 0;

  Future<void> _refresh() async {
    if (isClosed) {
      return;
    }

    final sequence = ++_sequence;

    final drivesState = _drivesCubit.state;

    // The drive-list read this page is waiting on, when that is what is
    // running. The whole state, because it has two phases with two different
    // things to say and this is not the place to choose between them.
    final loadingSync = _syncCubit.state;
    final loading = loadingSync is SyncLoadingDrives
        ? DrivesListLoading(syncState: loadingSync)
        : const DrivesListLoading();

    // Still looking. Never "you have none" - that is the whole point of the
    // state beneath this one.
    if (drivesState is! DrivesLoadSuccess) {
      emit(loading);
      return;
    }

    if (drivesState.hasNoDrives) {
      // A look this page started is still running. "We have not found any
      // yet" is not "there are none", and this is the decision where the
      // difference has to be kept - not in the widget, and not in whichever
      // state happens to land first.
      if (_refreshesWeStarted > 0) {
        emit(loading);
        return;
      }

      // The drives cubit can lag the table it watches by a beat: a refresh
      // writes the drives it found and the watch fires afterwards. A "none"
      // the table already disagrees with is a stale answer, not an empty
      // account, so the page waits for the cubit to catch up rather than
      // publishing it.
      if (await _localTableHasDrives()) {
        if (isClosed || sequence != _sequence) {
          return;
        }

        emit(loading);
        return;
      }

      if (isClosed || sequence != _sequence) {
        return;
      }

      // We asked and could not find out, which is not the same as an empty
      // account. Same rule the explorer panel uses, read off the same cubit,
      // so the two can never disagree.
      emit(
        _syncCubit.driveListRefreshFailed
            ? DrivesListUnavailable()
            : DrivesListEmpty(),
      );
      return;
    }

    final Map<String, DriveContentSummary> summaries;
    try {
      summaries = await _driveDao.driveContentSummaries();
    } catch (e, stackTrace) {
      // The drives themselves are in hand; only the per-drive numbers are not.
      // Draw the list without them rather than losing the page over a count.
      logger.e('Could not read the per-drive content summaries', e, stackTrace);
      _emitDrives(drivesState, const {}, const {}, sequence);
      return;
    }

    Map<String, DateTime> lastSyncedAt = const {};
    try {
      final preferences = _userPreferencesRepository.currentPreferences ??
          await _userPreferencesRepository.load();
      lastSyncedAt = preferences.driveLastSyncedAt;
    } catch (e, stackTrace) {
      logger.e(
          'Could not read when the drives were last synced', e, stackTrace);
    }

    _emitDrives(drivesState, summaries, lastSyncedAt, sequence);
  }

  /// Whether the local table holds any drive at all.
  ///
  /// A local read, like everything else this page does. Only ever asked when
  /// the drives cubit says there are none, which is the one answer worth
  /// double-checking.
  Future<bool> _localTableHasDrives() async {
    try {
      return (await _driveDao.allDrives().get()).isNotEmpty;
    } catch (e, stackTrace) {
      logger.e('Could not check the local drives table', e, stackTrace);

      return false;
    }
  }

  void _emitDrives(
    DrivesLoadSuccess drivesState,
    Map<String, DriveContentSummary> summaries,
    Map<String, DateTime> lastSyncedAt,
    int sequence,
  ) {
    if (isClosed || sequence != _sequence) {
      return;
    }

    final sharedDriveIds = drivesState.sharedDrives.map((d) => d.id).toSet();

    // One list, sorted as a whole. Shared drives are marked in place rather
    // than pushed into a second section nobody scrolls to.
    // Assembled in name order and re-sorted below once the rows carry the
    // figures the other columns order by - file counts and sizes are not on
    // the drive record, so nothing but name can be sorted at this point.
    final drives = [...drivesState.userDrives, ...drivesState.sharedDrives]
      ..sort((a, b) => compareAlphabeticallyAndNatural(a.name, b.name));

    final syncState = _syncCubit.state;
    final syncingDriveId = _syncCubit.syncingDriveId;

    // The top bar says "1 of 5 drives failed" and the list is where a reader
    // goes to find out which. The state has always carried the ids; nothing on
    // this page read them.
    final failedDriveIds = syncState is SyncCompleteWithErrors
        ? syncState.failedDriveIds.toSet()
        : const <String>{};

    final items = drives.map((drive) {
      final syncedAt = lastSyncedAt[drive.id];

      // Either the history was walked - which is what a block height means -
      // or we watched a sync of it finish. Before either, every number derived
      // from the local tables is a zero standing in for "we have not looked".
      final hasBeenWalked =
          (drive.lastBlockHeight ?? 0) > 0 || syncedAt != null;

      final summary = summaries[drive.id] ?? DriveContentSummary.empty;

      return DriveListItem(
        id: drive.id,
        name: drive.name,
        isPrivate: drive.privacy == DrivePrivacyTag.private,
        isSharedWithMe: sharedDriveIds.contains(drive.id),
        isHidden: drive.isHidden,
        dateCreated: drive.dateCreated,
        hasBeenWalked: hasBeenWalked,
        fileCount: hasBeenWalked ? summary.fileCount : null,
        totalSize: hasBeenWalked ? summary.totalSize : null,
        lastSyncedAt: syncedAt,
        isSyncing: syncState is SyncInProgress &&
            (syncingDriveId == null || syncingDriveId == drive.id),
        lastSyncFailed: failedDriveIds.contains(drive.id),
      );
    }).toList();

    // Counted over everything, filtered to one scope. A scope reading zero is
    // exactly the fact a reader wants before clicking it, so the counts cannot
    // come from the filtered list.
    final shown = items.where(_scope.matches).toList()
      ..sort(_sort.comparator(ascending: _sortAscending));

    emit(DrivesListLoaded(
      drives: shown,
      scope: _scope,
      counts: DriveScopeCounts.of(items),
      sort: _sort,
      sortAscending: _sortAscending,
    ));
  }

  /// Which column the list is ordered by, and which way.
  DriveListSort _sort = DriveListSort.name;
  bool _sortAscending = true;

  /// Orders the list by [sort].
  ///
  /// Asking for the column that is already ordering reverses it, which is what
  /// a second click on a table heading does everywhere. Moving to a different
  /// column starts ascending - except the three that can be unknown, where
  /// descending first is the useful answer: the largest drive, the one with
  /// most files, the one synced most recently. Nobody opens a table of sizes
  /// to find the smallest.
  void sortBy(DriveListSort sort) {
    if (_sort == sort) {
      _sortAscending = !_sortAscending;
    } else {
      _sort = sort;
      _sortAscending = sort == DriveListSort.name;
    }

    // Reordered in place rather than through `_refresh`, which emits a loading
    // state and re-reads the summaries: neither the drives nor their figures
    // changed, and flashing "Loading your drives..." because somebody clicked
    // a column heading would be a lie about what is happening.
    final current = state;

    if (current is! DrivesListLoaded) {
      return;
    }

    emit(DrivesListLoaded(
      drives: [...current.drives]
        ..sort(_sort.comparator(ascending: _sortAscending)),
      scope: current.scope,
      counts: current.counts,
      sort: _sort,
      sortAscending: _sortAscending,
    ));
  }

  /// Which drives the list is showing. See [DriveScope].
  DriveScope _scope = DriveScope.all;

  DriveScope get scope => _scope;

  /// Narrows the list, from the sidebar.
  ///
  /// The scope is this cubit's rather than the page's because the sidebar sets
  /// it and the table reads it, and they are on opposite sides of the shell.
  void showScope(DriveScope scope) {
    if (_scope == scope) {
      return;
    }

    _scope = scope;
    _refresh();
  }

  /// Runs the drive-list refresh again after one failed.
  ///
  /// The same request that failed - the one the login path runs - and nothing
  /// more. It does not walk any drive's history and does not touch the user's
  /// sync-on-login preference.
  Future<void> retryLoadingDrives() async {
    if (state is! DrivesListUnavailable) {
      return;
    }

    _refreshesWeStarted++;
    emit(const DrivesListLoading());

    try {
      await _syncCubit.syncMetadataOnly();
    } finally {
      _refreshesWeStarted--;

      // Decide from what the retry actually produced. Every emission it made
      // on the way through was answered with "still looking", and this is the
      // one that is allowed to say anything else.
      await _refresh();
    }
  }

  /// Walks every drive, once, because the user asked.
  ///
  /// [SyncTrigger.userInitiated], because that is who asked. It ran as
  /// background to keep the old blocking modal off a list the user was
  /// reading - but that modal is gone, the summary that replaced it neither
  /// scrims nor takes a click, and the only thing the trigger still decides is
  /// what the sync history records. Recording a pressed button as "Automatic"
  /// was simply wrong.
  void syncAllDrives() {
    unawaited(_syncCubit.startSync());
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
