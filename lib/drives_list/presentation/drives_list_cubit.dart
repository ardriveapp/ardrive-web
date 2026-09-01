import 'dart:async';

import 'package:ardrive/blocs/drives/drives_cubit.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
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

    // How far the drive-list read has got, when that is what is running. Zero
    // otherwise, and `hasCount` keeps "0 of 0" off the screen.
    final loading = _syncCubit.state is SyncLoadingDrives
        ? DrivesListLoading(
            drivesRead: (_syncCubit.state as SyncLoadingDrives).drivesRead,
            drivesFound: (_syncCubit.state as SyncLoadingDrives).drivesFound,
          )
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

    emit(DrivesListLoaded(drives: items));
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
  /// [SyncTrigger.background] deliberately: this page is a list the user is
  /// reading, and a sync started from it must not drop a scrim over it. The
  /// top bar and each row report it instead.
  void syncAllDrives() {
    unawaited(_syncCubit.startSync(trigger: SyncTrigger.background));
  }

  /// Starts a sync for one drive that has never been walked, because it is
  /// being opened.
  ///
  /// Choosing a drive is the act that fetches it. Without this, opening a
  /// never-synced drive landed on the "Drive Not Synced" card and waited for a
  /// second, manual press - the list had already told the user the drive was
  /// never synced, and then made them say so again.
  ///
  /// A drive that has already been walked is left alone: opening it must not
  /// cost a network round trip.
  ///
  /// [SyncTrigger.background] deliberately. The user is on their way into a
  /// drive, and a sync started on the way must not drop a scrim over where
  /// they are going. The explorer's own panel reports it instead.
  ///
  /// Taken by id rather than as a [DriveListItem], and both questions answered
  /// here rather than off the item: the item a row was drawn with is a
  /// snapshot of a frame that may be several syncs old, and `isSyncing` on it
  /// is true for every row while an all-drives sync runs. Deciding off the
  /// rendered item is how a tap silently started nothing.
  void syncDriveIfNeverSynced(String driveId) {
    final state = this.state;

    if (state is! DrivesListLoaded) {
      return;
    }

    for (final drive in state.drives) {
      if (drive.id != driveId) {
        continue;
      }

      // Already walked: it opens straight to its contents, as it did before.
      if (drive.hasBeenWalked) {
        return;
      }

      // A sync already covering this drive is the fetch. Starting a second one
      // would only queue behind it.
      if (_syncIsCovering(driveId)) {
        return;
      }

      // A sync running for a *different* drive is refused here - one at a
      // time, no queue - and this call returns having started nothing. That
      // is deliberate and it is not hidden: the panel the user lands on says
      // that another drive is syncing and that this one was not started, so
      // the offer to sync it is theirs to take when that one ends. See
      // `DriveDetailUnsyncedCard`.
      unawaited(
        _syncCubit.startSyncForDrive(
          driveId: driveId,
          trigger: SyncTrigger.background,
        ),
      );

      return;
    }
  }

  /// Whether a sync running right now already covers [driveId] - either this
  /// drive's own, or an all-drives sync, which covers every drive.
  bool _syncIsCovering(String driveId) {
    if (_syncCubit.state is! SyncInProgress) {
      return false;
    }

    final syncingDriveId = _syncCubit.syncingDriveId;

    return syncingDriveId == null || syncingDriveId == driveId;
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
