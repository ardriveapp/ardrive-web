import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/user_utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:rxdart/rxdart.dart';

part 'drive_detail_state.dart';

/// Sentinel used by copyWith to distinguish "not provided" from "explicitly null".
const _driveDetailAbsent = Object();

/// How often a folder may redraw while a sync is writing its drive.
///
/// A starting point, not a measured optimum. Each redraw parses the folder's
/// rows and rebuilds its breadcrumb, so the cost scales with folder size while
/// the tick rate scales with how fast revisions land - two things that are
/// worst at the same time, on a big drive's first walk.
///
/// To tune it: watch redraws per second on a drive with thousands of revisions
/// and raise this until the list stops feeling busy without feeling stale. The
/// floor is set by how long a redraw takes, not by taste.
const Duration _folderRedrawInterval = Duration(milliseconds: 500);

class DriveDetailCubit extends Cubit<DriveDetailState> {
  String _driveId;

  /// The ID of the drive currently being viewed or loaded.
  String get currentDriveId => _driveId;
  final ProfileCubit _profileCubit;
  final DriveDao _driveDao;
  final ConfigService _configService;
  final ArDriveAuth _auth;
  final ActivityTracker _activityTracker;
  final BreadcrumbBuilder _breadcrumbBuilder;
  final SyncCubit _syncCubit;

  final DriveRepository _driveRepository;

  StreamSubscription? _folderSubscription;
  StreamSubscription? _syncSubscription;
  bool _initialLoadComplete = false;

  /// When this folder last redrew while a sync was writing its drive.
  DateTime? _lastFolderRedraw;

  /// Whether a redraw was dropped by the throttle and not yet made good.
  bool _droppedFolderRedraw = false;

  /// What was last drawn, so a tick that changes nothing can be recognised.
  FolderWithContents? _lastFolderContents;
  bool _isExplicitSync = false;

  /// Bumped by every [openFolder]. Cancelling `_folderSubscription` does not
  /// cancel a callback that already began awaiting, so an in-flight load can
  /// still emit after the user has navigated somewhere else in the same drive
  /// - where the `_driveId` checks cannot see it, because the drive did not
  /// change. Callbacks capture this and drop their result if it moved on.
  int _folderLoadGeneration = 0;
  final _defaultAvailableRowsPerPage = [25, 50, 75, 100];

  List<ArDriveDataTableItem> _selectedItems = [];
  List<ArDriveDataTableItem> get selectedItems => _selectedItems;

  List<FileDataTableItem>? _allImagesOfCurrentFolder;

  bool _forceDisableMultiselect = false;

  bool _refreshSelectedItem = false;

  DriveDetailCubit({
    required String driveId,
    String? initialFolderId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ConfigService configService,
    required ActivityTracker activityTracker,
    required ArDriveAuth auth,
    required BreadcrumbBuilder breadcrumbBuilder,
    required SyncCubit syncCubit,
    required DriveRepository driveRepository,
  })  : _profileCubit = profileCubit,
        _activityTracker = activityTracker,
        _driveDao = driveDao,
        _auth = auth,
        _configService = configService,
        _breadcrumbBuilder = breadcrumbBuilder,
        _syncCubit = syncCubit,
        _driveRepository = driveRepository,
        _driveId = driveId,
        super(DriveDetailLoadInProgress()) {
    _listenForSyncCompletion();

    if (driveId.isEmpty) {
      // No drive to open, but this cubit still shows the drive-list screens -
      // "loading", "none" and "could not be loaded" - so it has to keep
      // hearing about syncs. The subscription used to be registered below
      // this return, which meant a login at the root URL never heard one.
      return;
    }

    if (initialFolderId != null) {
      // TODO: Handle deep-linking folders of unattached drives.
      Future.microtask(() async {
        final folder = await _driveDao
            .folderById(folderId: initialFolderId)
            .getSingleOrNull();

        // Abort if user switched drives during the async operation
        if (_driveId != driveId) return;

        // Open the root folder if the deep-linked folder could not be found.
        openFolder(folderId: folder?.id);
        // The empty string here is required to open the root folder
      }).whenComplete(() {
        _initialLoadComplete = true;
      });
    } else {
      Future.microtask(() async {
        // No loading state to emit first: the cubit is constructed in
        // DriveDetailLoadInProgress, so the screen is already saying it is
        // working before this wait begins.
        // Wait only for a sync that could be writing *this* drive. Waiting
        // for any sync at all meant syncing drive B made drive A - already
        // walked, its rows untouched - unopenable until B finished.
        if (SyncCubit.syncTouchesDrive(
          state: _syncCubit.state,
          syncingDriveId: _syncCubit.syncingDriveId,
          completedDriveIds: _syncCubit.completedDriveIds,
          runDriveIds: _syncCubit.syncingDriveIds,
          driveId: driveId,
        )) {
          await _syncCubit.waitCurrentSync();
        }

        // Abort if user switched drives during sync wait
        if (_driveId != driveId) {
          return;
        }

        final drive =
            await _driveDao.driveById(driveId: driveId).getSingleOrNull();

        // Abort if user switched drives during the async operation
        if (_driveId != driveId) {
          return;
        }

        // Or if the session ended during it. This sits behind
        // `waitCurrentSync()`, which parks for the whole length of a running
        // sync; a logout in that window drops every local table, so the drive
        // really is gone by the time this resumes - and emitting into a closed
        // cubit throws into the zone rather than reporting anything.
        if (isClosed) {
          return;
        }

        // Check if drive exists
        if (drive == null) {
          emit(DriveDetailLoadNotFound());
          return;
        }

        // Open the drive regardless of lastBlockHeight.
        // Background sync will update via Drift streams.
        openFolder(folderId: drive.rootFolderId);
      }).whenComplete(() {
        _initialLoadComplete = true;
      });
    }

    // (registered by _listenForSyncCompletion, above)
  }

  /// Redraws once more if the throttle dropped the last tick of a run.
  ///
  /// The throttle is safe to drop ticks precisely because another is coming.
  /// The one tick that has nothing behind it is the last one of a sync, and
  /// dropping that leaves the folder one batch short of what was written with
  /// nothing else due to correct it. So a run that ends having dropped
  /// anything re-reads the folder, once.
  Future<void> _refreshAfterDroppedRedraws() async {
    if (!_droppedFolderRedraw) {
      return;
    }

    _droppedFolderRedraw = false;

    final current = state;

    if (isClosed || current is! DriveDetailLoadSuccess) {
      return;
    }

    // The folder that is open, re-read. Not a loading state: the reader is
    // looking at this list and nothing about it is being replaced.
    openFolder(folderId: current.folderInView.folder.id);
  }

  void _listenForSyncCompletion() {
    _syncSubscription = _syncCubit.stream.listen((syncState) {
      if (SyncCubit.syncHasFinished(syncState)) {
        _refreshAfterDroppedRedraws();
      }

      // A drive list that has since been read means the failure screen is out
      // of date, wherever the retry came from. The top bar has its own Try
      // Again, and without this the body would go on saying the drives could
      // not be loaded while the bar above it reported everything was fine.
      if (state is DriveDetailDrivesUnavailable &&
          SyncCubit.syncHasFinished(syncState) &&
          !_syncCubit.driveListRefreshFailed) {
        showEmptyDriveDetail();
        return;
      }

      if (_initialLoadComplete && SyncCubit.syncHasFinished(syncState)) {
        _onSyncCompleted();
      }
    });
  }

  /// Whether this drive's root folder metadata has actually been read.
  ///
  /// [DriveDetailLoadUnsynced] is entered when the root folder has no
  /// revision, so every path that leaves it has to test the same thing.
  /// Gating recovery on `lastBlockHeight` instead lets the two conditions
  /// disagree, and this is exactly the codebase where they do: a sync that
  /// writes the root revision and then fails before advancing the watermark
  /// leaves readable metadata behind a drive pinned on "Drive Not Synced",
  /// where the sync button only re-emits the same state.
  ///
  /// `lastBlockHeight` is still honoured, because a drive synced by an earlier
  /// build may have advanced its watermark and is by definition synced.
  Future<bool> _hasRootFolderMetadata(Drive drive) async {
    if ((drive.lastBlockHeight ?? 0) > 0) {
      return true;
    }

    final rootFolderRevision = await _driveDao
        .latestFolderRevisionByFolderId(
          driveId: drive.id,
          folderId: drive.rootFolderId,
        )
        .getSingleOrNull();

    return rootFolderRevision != null;
  }

  /// Called when sync completes. Re-checks drive state if we're showing
  /// unsynced or loading state, and loads the drive content if now available.
  Future<void> _onSyncCompleted() async {
    if (isClosed || _isExplicitSync) return;

    final currentState = state;
    if (currentState is DriveDetailLoadUnsynced) {
      final capturedDriveId = currentState.drive.id;

      final drive =
          await _driveDao.driveById(driveId: capturedDriveId).getSingleOrNull();

      if (isClosed) return;

      final newState = state;
      if (newState is! DriveDetailLoadUnsynced ||
          newState.drive.id != capturedDriveId) {
        return;
      }

      if (drive == null) {
        emit(DriveDetailLoadNotFound());
        return;
      }

      if (await _hasRootFolderMetadata(drive)) {
        if (isClosed || state is! DriveDetailLoadUnsynced) return;

        openFolder(folderId: drive.rootFolderId, otherDriveId: capturedDriveId);
      }
    }
  }

  /// Decides which of the three things an empty drive list means.
  ///
  /// It used to mean one: "Getting Started", two create-a-drive buttons and an
  /// empty sidebar, shown on EVERY login with an empty local database for the
  /// whole length of the drive-list fetch - because `DrivesCubit` reports the
  /// empty table the instant Drift reads it, and the wait here did not cover
  /// the fetch. [SyncCubit.waitCurrentSync] treats `SyncLoadingDrives` as
  /// finished on purpose, so folder opens do not hang behind a refresh, and
  /// that is precisely the state a metadata-only login sits in.
  ///
  /// So this waits on the drive list specifically - see
  /// [SyncCubit.waitForDriveListRefresh] - and then separates the three:
  /// still looking (the caller's [DriveDetailLoadInProgress] stands, and the
  /// explorer says the drives are loading), looked and found nothing
  /// ([DriveDetailLoadEmpty]), and could not look at all
  /// ([DriveDetailDrivesUnavailable]).
  Future<void> showEmptyDriveDetail() async {
    // Nothing to announce before this wait either. This runs when there is no
    // drive to show, from a state that is already DriveDetailLoadInProgress,
    // and all it can do afterwards is narrow that to "empty" - so emitting a
    // loading state here would claim work that is not happening.
    await _syncCubit.waitForDriveListRefresh();

    if (isClosed) {
      return;
    }

    // Check if state has already changed (e.g., drives were loaded during sync)
    // Don't overwrite a more specific state with the empty state.
    // Allow overwriting DriveDetailLoadInProgress only when no real drive is
    // being loaded (i.e., the cubit is still on its initial empty drive ID).
    if (state is DriveDetailLoadSuccess ||
        state is DriveDetailLoadUnsynced ||
        (state is DriveDetailLoadInProgress && _driveId.isNotEmpty)) {
      return;
    }

    // We asked and could not find out. Saying "you have no drives" here is the
    // one answer that is certainly wrong.
    if (_syncCubit.driveListRefreshFailed) {
      emit(DriveDetailDrivesUnavailable());
      return;
    }

    // And check, rather than infer. The login path only reaches here when
    // DrivesCubit already said the list was empty, but `retryLoadingDrives`
    // reaches it after a refresh that may well have found drives - and
    // claiming emptiness there would show "Getting Started" to a user who has
    // just been told their drives could not be loaded, which is the exact
    // thing this whole change exists to stop.
    final drives = await _driveDao.allDrives().get();
    if (isClosed) return;

    if (drives.isNotEmpty) {
      // Somebody else owns the next state: DrivesCubit will select one and the
      // page listener opens it.
      return;
    }

    emit(DriveDetailLoadEmpty());
  }

  /// Runs the drive-list refresh again after one failed, for the screen that
  /// told the user it had.
  ///
  /// [SyncCubit.syncMetadataOnly] and nothing more: it is the same request
  /// that failed, it is what the login path runs, and it leaves the user's
  /// syncAllDrivesOnLogin preference alone. The explorer goes back to saying
  /// the drives are loading while it runs, and lands on whichever of the three
  /// answers is true afterwards.
  Future<void> retryLoadingDrives() async {
    if (state is! DriveDetailDrivesUnavailable) {
      return;
    }

    emit(DriveDetailLoadInProgress());

    await _syncCubit.syncMetadataOnly();

    if (isClosed) {
      return;
    }

    await showEmptyDriveDetail();
  }

  Future<void> changeDrive(String driveId) async {
    // First check current drive state before waiting for sync
    var drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();

    // If drive doesn't exist locally at all, wait for sync to discover it.
    // This one already emits before it waits, which is the shape openFolder
    // now has too.
    if (drive == null) {
      emit(DriveDetailLoadInProgress());
      // Same gate as openFolder. A single-drive sync of another drive cannot
      // discover this one - only a drive-list refresh does that, and
      // syncTouchesDrive already treats one as covering everything - so
      // waiting for it would just postpone the same answer.
      if (SyncCubit.syncTouchesDrive(
        state: _syncCubit.state,
        syncingDriveId: _syncCubit.syncingDriveId,
        completedDriveIds: _syncCubit.completedDriveIds,
        runDriveIds: _syncCubit.syncingDriveIds,
        driveId: driveId,
      )) {
        await _syncCubit.waitCurrentSync();
      }
      drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();
    }

    if (drive == null) {
      emit(DriveDetailLoadNotFound());
      return;
    }

    // Proceed to open the drive regardless of lastBlockHeight.
    // The local DB has whatever the user created or last synced.
    // Background sync will update via Drift streams if anything new appears.

    await _folderSubscription?.cancel();

    // If the drive info panel is open (selectedItem is a DriveDataItem),
    // keep it open and let openFolder update it to the new drive.
    // Otherwise, clear the selected item to avoid showing stale file/folder data.
    if (_selectedItem is! DriveDataItem) {
      _selectedItem = null;
    } else {
      // Enable refresh so the subscription callback updates the drive info
      _refreshSelectedItem = true;
    }

    _driveId = driveId;

    openFolder(folderId: drive.rootFolderId);
  }

  Future<void> openFolder({
    String? folderId,
    String? otherDriveId,
    String? selectedItemId,
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) async {
    // Claimed before the first await, so anything already in flight for a
    // previous folder is stale from here on even when the drive is unchanged.
    final loadGeneration = ++_folderLoadGeneration;

    // A new folder redraws immediately whatever the last one did: the throttle
    // exists to stop a folder flickering as it fills, not to delay one being
    // opened.
    _lastFolderRedraw = null;
    _droppedFolderRedraw = false;
    _lastFolderContents = null;

    if (isClosed) {
      return;
    }

    // `changeDrive` has already cancelled the folder subscription and moved
    // `_driveId` by the time it gets here, so until this emits, the screen
    // still shows the drive the user just left. Saying so is what makes a
    // click on a drive feel answered.
    //
    // There is no wait behind it any more - see below - so this is a moment,
    // not a screen anybody sits on.
    //
    // Except when the drive is already on screen. Navigating a folder inside a
    // drive that is syncing threw the reader out of the drive entirely and
    // onto the full-panel "this drive is syncing" card - they lost the folder
    // they were reading to acknowledge a click on the folder beside it. The
    // drive they are looking at stays up instead, and the new folder replaces
    // it when there is one to show. The sync is already reported by the ring
    // in the top bar, so nothing goes unsaid.
    final showingThisDriveAlready = state is DriveDetailLoadSuccess &&
        (state as DriveDetailLoadSuccess).currentDrive.id ==
            (otherDriveId ?? _driveId);

    if (!showingThisDriveAlready) {
      emit(DriveDetailLoadInProgress());
    }

    // No wait. A folder is read from committed transactions, so what comes
    // back mid-sync is consistent - it is simply less than the folder will
    // eventually hold, and the subscription above fills the rest in as it
    // lands. Waiting here bought nothing a reader wanted and cost them the
    // drive for the length of the run.
    //
    // The one wait that stays is `changeDrive`'s, and it is a different
    // question: there the drive is not in the local database at all, and only
    // a sync will produce it. Waiting for a row that might arrive is worth
    // doing; waiting to read rows that are already there is not.

    // A newer openFolder claimed the generation while this one waited - it
    // owns the subscription and the state now, so this one stops here rather
    // than mounting a second listener for a folder nobody is looking at.
    if (isClosed || loadGeneration != _folderLoadGeneration) {
      return;
    }

    try {
      _allImagesOfCurrentFolder = null;

      String driveId = otherDriveId ?? _driveId;

      await _folderSubscription?.cancel();

      _folderSubscription =
          Rx.combineLatest3<Drive?, FolderWithContents, ProfileState, void>(
        _driveRepository.watchDrive(driveId: driveId),
        _driveDao
            .watchFolderContents(
          driveId,
          orderBy: contentOrderBy,
          orderingMode: contentOrderingMode,
          folderId: folderId,
        )
            .handleError((error, stack) {
          logger.e('Error watching folder contents', error, stack);
          if (error is DriveNotFoundException) {
            emit(DriveDetailLoadNotFound());
          } else if (error is FolderNotFoundInDriveException) {
            _handleFolderNotFound(error.driveId);
          }
        }),
        _profileCubit.stream.startWith(ProfileCheckingAvailability()),
        (drive, folderContents, _) async {
          if (isClosed) {
            return;
          }

          if (driveId != _driveId) {
            return;
          }

          // Most ticks carry nothing new, so the cheapest question first.
          //
          // Drift re-runs a watched query when the *tables* it reads change,
          // not when its own result does. A sync writing folder X therefore
          // re-emits folder Y - the one on screen - with contents identical to
          // what is already drawn, once per batch for the length of the run.
          // Those redraws are pure waste: they parse the same rows, rebuild
          // the same breadcrumb and emit the same list.
          //
          // FolderWithContents is Equatable, so this is exact rather than a
          // heuristic: skip only when nothing a reader could see has changed.
          // Unlike the interval below it, this never delays anything - a tick
          // that carries a real change is never the one dropped here.
          if (_lastFolderContents == folderContents &&
              this.state is DriveDetailLoadSuccess) {
            return;
          }

          // Coalesced, not held.
          //
          // This used to await the whole sync, which is why a drive being
          // synced could not be read: the folder on screen went as stale as
          // the run was long. The reason for the hold was churn, not
          // correctness - every batch commits in its own transaction, so a
          // read mid-sync gets consistent data, just less of it than it will
          // eventually have. So the fix is to redraw *less often*, not to stop
          // redrawing: the folder fills in while the sync runs.
          //
          // The first tick after a folder opens is never dropped, so opening a
          // drive mid-sync is immediate. After that, at most one redraw per
          // [_folderRedrawInterval] for as long as a sync is writing this
          // drive; once nothing is, every tick lands as before.
          if (SyncCubit.syncTouchesDrive(
            state: _syncCubit.state,
            syncingDriveId: _syncCubit.syncingDriveId,
            completedDriveIds: _syncCubit.completedDriveIds,
            runDriveIds: _syncCubit.syncingDriveIds,
            driveId: driveId,
          )) {
            final last = _lastFolderRedraw;
            final now = DateTime.now();

            if (last != null && now.difference(last) < _folderRedrawInterval) {
              // Dropped, and remembered as dropped. A run that ends on a
              // dropped tick would otherwise leave the folder one batch short
              // of what was written, with nothing else coming to correct it -
              // see [_refreshAfterDroppedRedraws].
              _droppedFolderRedraw = true;
              return;
            }

            _lastFolderRedraw = now;
          }

          if (drive == null) {
            emit(DriveDetailLoadNotFound());
            return;
          }

          if (_activityTracker.isUploading) {
            // Dropped, and owed back. An upload writes its file while this
            // flag is up, so the tick carrying it is the one refused here -
            // and nothing else is going to write that folder afterwards, so
            // no later tick will carry it either. Remembering the debt is what
            // lets the refresh at the end of the upload settle it.
            _droppedFolderRedraw = true;
            return;
          }

          // Recorded here, past every early return above it, because it means
          // "this is what the reader is looking at" - and a tick dropped by
          // one of those returns was never drawn.
          //
          // Recording it earlier was a real bug and the upload path was where
          // it bit: an upload writes the new file, the tick carrying it is
          // dropped by the guard just above, and the next identical tick then
          // matched what had been recorded and was skipped as a no-op. The
          // file did not appear until something else changed the folder.
          _lastFolderContents = folderContents;

          final state = this.state is DriveDetailLoadSuccess
              ? this.state as DriveDetailLoadSuccess
              : null;

          final profile = _profileCubit.state;

          final availableRowsPerPage = calculateRowsPerPage(
            folderContents.files.length + folderContents.subfolders.length,
          );

          if (_selectedItem != null && _refreshSelectedItem) {
            if (_selectedItem is FileDataTableItem) {
              final index = folderContents.files.indexWhere(
                (element) => element.id == _selectedItem!.id,
              );

              if (index >= 0) {
                final item = folderContents.files[index];

                _selectedItem = DriveDataTableItemMapper.toFileDataTableItem(
                  item,
                  _selectedItem!.index,
                  _selectedItem!.isOwner,
                );
              }
            } else if (_selectedItem is FolderDataTableItem) {
              final index = folderContents.subfolders.indexWhere(
                (element) => element.id == _selectedItem!.id,
              );
              if (index >= 0) {
                final item = folderContents.subfolders[index];

                _selectedItem = DriveDataTableItemMapper.fromFolderEntry(
                  item,
                  _selectedItem!.index,
                  _selectedItem!.isOwner,
                );
              }
            } else {
              _selectedItem = DriveDataTableItemMapper.fromDrive(
                drive,
                (item) => null,
                0,
                _selectedItem!.isOwner,
              );
            }
          }

          final driveIsEmpty =
              folderContents.files.isEmpty && folderContents.subfolders.isEmpty;

          // A drive that renders with nothing in it is ambiguous: it may be
          // genuinely empty, or its contents may simply never have synced.
          // Telling someone their drive is empty when we have not actually
          // read it reads as "my data is gone", so only claim emptiness we
          // can back up. Otherwise fall through to DriveDetailLoadUnsynced,
          // which already says "Drive Not Synced" and offers to sync.
          //
          // The root folder's revision is the honest signal for that. A drive
          // created in this app writes one at creation time
          // (DriveCreateCubit), and sync writes one when the real metadata
          // lands - but a drive merely discovered by updateUserDrives has only
          // the placeholder folder row until then. lastBlockHeight cannot
          // answer this: it defaults to 0, so a freshly created empty drive is
          // indistinguishable from one that has never synced.
          if (driveIsEmpty && folderContents.folder.id == drive.rootFolderId) {
            final rootFolderRevision = await _driveDao
                .latestFolderRevisionByFolderId(
                  driveId: driveId,
                  folderId: drive.rootFolderId,
                )
                .getSingleOrNull();

            if (isClosed ||
                driveId != _driveId ||
                loadGeneration != _folderLoadGeneration) {
              return;
            }

            if (rootFolderRevision == null) {
              // Unless a sync is writing this drive right now, in which case
              // the root revision has simply not landed *yet*.
              //
              // Reading no longer waits for the sync - which is the point -
              // so this branch is now reached mid-walk, where it used not to
              // be. Saying "Drive Not Synced" then is wrong twice over: it
              // contradicts the ring still turning in the top bar, and it
              // offers a Sync Now that the cubit will refuse because a sync is
              // already running. Left on the loading panel, the drive opens by
              // itself the moment its root revision is written.
              if (SyncCubit.syncTouchesDrive(
                state: _syncCubit.state,
                syncingDriveId: _syncCubit.syncingDriveId,
                completedDriveIds: _syncCubit.completedDriveIds,
                runDriveIds: _syncCubit.syncingDriveIds,
                driveId: driveId,
              )) {
                if (this.state is! DriveDetailLoadSuccess) {
                  emit(DriveDetailLoadInProgress());
                }

                return;
              }

              emit(DriveDetailLoadUnsynced(drive: drive));
              return;
            }
          }

          final currentFolderContents = parseEntitiesToDatatableItem(
            folder: folderContents,
            isOwner: isDriveOwner(_auth, drive.ownerAddress),
          );

          if (selectedItemId != null) {
            _selectedItem = currentFolderContents.firstWhere(
              (element) => element.id == selectedItemId,
            );
          }

          final List<BreadCrumbRowInfo> pathSegments =
              await _breadcrumbBuilder.buildForFolder(
            folderId: folderContents.folder.id,
            rootFolderId: drive.rootFolderId,
            driveId: driveId,
          );

          if (isClosed ||
              driveId != _driveId ||
              loadGeneration != _folderLoadGeneration) {
            return;
          }

          if (state != null) {
            emit(
              state.copyWith(
                selectedItem: _selectedItem,
                currentDrive: drive,
                hasWritePermissions: profile is ProfileLoggedIn &&
                    drive.ownerAddress == profile.user.walletAddress,
                folderInView: folderContents,
                contentOrderBy: contentOrderBy,
                contentOrderingMode: contentOrderingMode,
                rowsPerPage: availableRowsPerPage.first,
                availableRowsPerPage: availableRowsPerPage,
                currentFolderContents: currentFolderContents,
                pathSegments: pathSegments,
                driveIsEmpty: driveIsEmpty,
                showSelectedItemDetails: _selectedItem != null,
              ),
            );
          } else {
            final columnsVisibility = await getTableColumnVisibility();

            if (isClosed ||
                driveId != _driveId ||
                loadGeneration != _folderLoadGeneration) {
              return;
            }

            emit(
              DriveDetailLoadSuccess(
                pathSegments: pathSegments,
                selectedItem: _selectedItem,
                currentDrive: drive,
                hasWritePermissions: profile is ProfileLoggedIn &&
                    drive.ownerAddress == profile.user.walletAddress,
                folderInView: folderContents,
                contentOrderBy: contentOrderBy,
                contentOrderingMode: contentOrderingMode,
                rowsPerPage: availableRowsPerPage.first,
                availableRowsPerPage: availableRowsPerPage,
                driveIsEmpty: driveIsEmpty,
                multiselect: false,
                currentFolderContents: currentFolderContents,
                columnVisibility: columnsVisibility,
                showSelectedItemDetails: _selectedItem != null,
              ),
            );
          }
        },
      ).listen((_) {});
    } catch (e, stacktrace) {
      logger.e('An error occured mouting the drive explorer', e, stacktrace);
    }

    _folderSubscription?.onError((e) async {
      if (e is FolderNotFoundInDriveException) {
        await _handleFolderNotFound(e.driveId);
        return;
      }

      if (e is DriveNotFoundException) {
        emit(DriveDetailLoadNotFound());
        return;
      }

      logger.e('An error occured mouting the drive explorer', e);
    });

    await _folderSubscription?.asFuture();
  }

  List<ArDriveDataTableItem> parseEntitiesToDatatableItem({
    required FolderWithContents folder,
    required bool isOwner,
  }) {
    int index = 0;

    final folders = folder.subfolders.map(
      (folder) => DriveDataTableItemMapper.fromFolderEntry(
        folder,
        index++,
        isOwner,
      ),
    );

    final files = folder.files.map(
      (file) => DriveDataTableItemMapper.toFileDataTableItem(
        file,
        index++,
        isOwner,
      ),
    );

    final items = [
      ...folders,
      ...files,
    ];

    return items;
  }

  List<int> calculateRowsPerPage(int totalEntries) {
    List<int> availableRowsPerPage;
    if (totalEntries < _defaultAvailableRowsPerPage.first) {
      availableRowsPerPage = <int>[totalEntries];
    } else {
      availableRowsPerPage = _defaultAvailableRowsPerPage;
    }
    return availableRowsPerPage;
  }

  Future<void> selectDataItem(ArDriveDataTableItem item,
      {bool openSelectedPage = false}) async {
    var state = this.state as DriveDetailLoadSuccess;

    if (state.currentDrive.isPublic && item is FileDataTableItem) {
      final dataTxId = item.dataTxId;
      state = state.copyWith(
          selectedFilePreviewUrl:
              '${_configService.config.arweaveGatewayForDataRequest.url}/$dataTxId');
    }

    _selectedItem = item;

    int? selectedPage;

    if (openSelectedPage) {
      selectedPage =
          state.currentFolderContents.indexOf(item) ~/ state.rowsPerPage;
    }

    emit(
      state.copyWith(
        selectedItem: item,
        showSelectedItemDetails: true,
        selectedPage: selectedPage,
        forceRebuildKey: selectedPage != null ? UniqueKey() : null,
      ),
    );
  }

  ArDriveDataTableItem? _selectedItem;

  ArDriveDataTableItem? get selectedItem => _selectedItem;

  Future<void> selectItems(List<ArDriveDataTableItem> items) async {
    var state = this.state as DriveDetailLoadSuccess;

    bool hasFolderSelected = false;

    if (items.any((element) => element is FolderDataTableItem)) {
      hasFolderSelected = true;
    }

    _selectedItems = items;

    if (items.isEmpty) {
      emit(state.copyWith(multiselect: false, hasFoldersSelected: false));
    } else {
      emit(state.copyWith(
        multiselect: true,
        hasFoldersSelected: hasFolderSelected,
      ));
    }
  }

  Future<void> unselectItem(SelectedItem selectedItem) async {
    var state = this.state as DriveDetailLoadSuccess;
    final updatedSelectedItems = state.selectedItems
        .where((element) => element.id != selectedItem.id)
        .toList();
    state = state.multiselect
        ? state.copyWith(selectedItems: updatedSelectedItems)
        : state.copyWith(selectedItems: []);

    emit(state);
    // Close multiselect automatically if no file is selected
    if (state.selectedItems.isEmpty && state.multiselect) {
      state = state.copyWith(multiselect: false);
      Future.delayed(
        const Duration(milliseconds: 10),
      ).then((value) => emit(state));
    }
  }

  void setMultiSelect(bool multiSelect) {
    final state = this.state as DriveDetailLoadSuccess;

    if (state.multiselect == multiSelect) return;

    if (!multiSelect) {
      clearSelection();
    }

    if (_selectedItems.isNotEmpty) {
      emit(state.copyWith(multiselect: true));
    } else {
      emit(state.copyWith(multiselect: false));
    }
  }

  Future<void> clearSelection() async {
    _selectedItems.clear();
  }

  bool get forceDisableMultiselect {
    if (_forceDisableMultiselect) {
      _forceDisableMultiselect = false;
      return true;
    }

    return false;
  }

  set forceDisableMultiselect(bool value) {
    _forceDisableMultiselect = value;
  }

  Future<void> launchPreview(TxID dataTxId) => openUrl(
      url:
          '${_configService.config.arweaveGatewayForDataRequest.url}/$dataTxId');

  void sortFolder({
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) {
    final state = this.state as DriveDetailLoadSuccess;
    openFolder(
      folderId: state.folderInView.folder.id,
      contentOrderBy: contentOrderBy,
      contentOrderingMode: contentOrderingMode,
    );
  }

  void toggleSelectedItemDetails() {
    final state = this.state as DriveDetailLoadSuccess;
    if (state.showSelectedItemDetails) {
      _selectedItem = null;
    }

    emit(
      state.copyWith(showSelectedItemDetails: !state.showSelectedItemDetails),
    );
  }

  /// Redraws the table, re-reading the folder first if anything was missed.
  ///
  /// The re-read is the half this did not do, and an upload is where that
  /// showed: the file is written while `isUploading` is up, the tick carrying
  /// it is refused by the guard in the subscription, and nothing writes that
  /// folder again afterwards - so there is no later tick to carry it. This
  /// then re-emitted the state it already had with a new key, which rebuilds
  /// the same rows. The file was uploaded, and was not on screen.
  ///
  /// Only when something was actually dropped, so the callers that use this
  /// for a cosmetic rebuild after a rename or a hide still pay nothing.
  void refreshDriveDataTable() async {
    _refreshSelectedItem = true;

    // Something the reader did wrote to the drive, so something may now be
    // waiting to be mined.
    //
    // An upload is not the only thing that leaves a pending transaction:
    // creating a drive or a folder, renaming one, moving files, assigning a
    // licence and taking a snapshot all write revisions the same way. Starting
    // the watch only from the upload form would confirm uploads and leave
    // every other write unconfirmed until the next login, which is the gap
    // this exists to close. This is the one seam nearly all of them already
    // pass through.
    //
    // Costs a single local read when nothing is pending, and stops - see
    // [SyncCubit.watchForPendingConfirmations].
    _syncCubit.watchForPendingConfirmations();

    if (_droppedFolderRedraw) {
      await _refreshAfterDroppedRedraws();
      return;
    }

    if (state is DriveDetailLoadSuccess) {
      await Future.delayed(const Duration(milliseconds: 100));
      final state = this.state as DriveDetailLoadSuccess;
      emit(state.copyWith(
        forceRebuildKey: UniqueKey(),
      ));
    }
  }

  bool canNavigateThroughImages(bool showHiddenImages) {
    final numberOfImages = getAllImagesOfCurrentFolder(showHiddenImages).length;
    return numberOfImages > 1;
  }

  Future<void> selectNextImage(bool showHiddenImages) =>
      _selectImageRelativeToCurrent(1, showHiddenImages);
  Future<void> selectPreviousImage(bool showHiddenImages) =>
      _selectImageRelativeToCurrent(-1, showHiddenImages);

  Future<void> _selectImageRelativeToCurrent(
      int offset, bool showHiddenImages) async {
    final currentIndex = getIndexForImage(
      _selectedItem as FileDataTableItem,
      showHiddenImages,
    );
    final nextIndex = currentIndex + offset;
    final nextImage = getImageForIndex(nextIndex, showHiddenImages);

    await selectDataItem(nextImage);
  }

  FileDataTableItem getImageForIndex(int index, bool showHiddenImages) {
    final allImagesOfCurrentFolder =
        getAllImagesOfCurrentFolder(showHiddenImages);
    final cyclicIndex = index % allImagesOfCurrentFolder.length;
    final image = allImagesOfCurrentFolder[cyclicIndex];

    return image;
  }

  int getIndexForImage(FileDataTableItem image, bool showHiddenImages) {
    final allImagesOfCurrentFolder =
        getAllImagesOfCurrentFolder(showHiddenImages);
    final index = allImagesOfCurrentFolder.indexWhere(
      (element) => element.id == image.id,
    );

    return index;
  }

  List<FileDataTableItem> getAllImagesOfCurrentFolder(bool showHiddenImages) {
    if (_allImagesOfCurrentFolder != null) {
      return _allImagesOfCurrentFolder!;
    }

    final state = this.state as DriveDetailLoadSuccess;

    final List<FileDataTableItem> allImagesForFolder =
        state.currentFolderContents.whereType<FileDataTableItem>().where(
      (element) {
        final supportedImageType = supportedImageTypesInFilePreview.contains(
          element.contentType,
        );

        return supportedImageType &&
            (showHiddenImages ? true : !element.isHidden);
      },
    ).toList();

    _allImagesOfCurrentFolder = allImagesForFolder;

    return allImagesForFolder;
  }

  Future<void> updateTableColumnVisibility(TableColumn column) async {
    (await _store()).putBool(
      'drive_detail_column_${column.index}',
      column.isVisible,
    );
  }

  Future<Map<int, bool>> getTableColumnVisibility() async {
    final columnVisibility = <int, bool>{};

    for (int i = 0; i < 5; i++) {
      final isVisible = (await _store()).getBool(
        'drive_detail_column_$i',
      );

      columnVisibility[i] = isVisible ?? true;
    }

    return columnVisibility;
  }

  Future<LocalKeyValueStore> _store() async {
    return LocalKeyValueStore.getInstance();
  }

  /// Syncs all drives and then refreshes the current drive view.
  Future<void> syncAllAndRefreshCurrentDrive() async {
    final currentState = state;
    if (currentState is DriveDetailLoadUnsynced) {
      final driveId = currentState.drive.id;
      final rootFolderId = currentState.drive.rootFolderId;

      _isExplicitSync = true;
      final bool synced;
      try {
        // Pressed, so the history has to say Manual. The panel reports the
        // sync itself while it runs; the summary at the end neither scrims nor
        // takes a click, so nothing is covered twice.
        emit(DriveDetailLoadInProgress());
        synced = await _syncCubit.startSync();
      } finally {
        _isExplicitSync = false;
      }

      // Whether a sync ran is the cubit's answer, not something to infer from
      // the state beforehand: it can also decline for a hidden tab, an
      // uninterruptible activity, or a cancellation, and every one of those
      // reads afterwards as a drive that is as empty as it was. Reporting what
      // a sync "found" when none ran is the one thing this panel must not do.
      if (!synced) {
        if (isClosed || _driveId != driveId) return;
        emit(currentState);
        return;
      }

      if (isClosed || _driveId != driveId) return;

      // The same rule as `syncCurrentDrive`, and the same reason: only a sync
      // that ran to the end may have its findings reported. This path had the
      // identical hole - it read the drive and reported what it found after a
      // sync that had failed on some drives, or on all of them.
      if (!_syncCubit.state.isSuccessfulCompletion) {
        // Back to the panel the press came from, rather than leaving the
        // explorer on a loading state that nothing else will replace.
        emit(currentState);
        return;
      }

      final drive =
          await _driveDao.driveById(driveId: driveId).getSingleOrNull();

      if (isClosed || _driveId != driveId) return;

      if (drive == null) {
        emit(DriveDetailLoadNotFound());
        return;
      }

      final hasRootFolderMetadata = await _hasRootFolderMetadata(drive);

      if (isClosed || _driveId != driveId) return;

      if (hasRootFolderMetadata) {
        openFolder(folderId: rootFolderId, otherDriveId: driveId);
      } else {
        // Same as syncCurrentDrive: a sync has looked, so the card says so
        // rather than repeating itself.
        emit(DriveDetailLoadUnsynced(drive: drive, syncFoundNothing: true));
      }
    }
  }

  /// Syncs the current unsynced drive and then opens it.
  Future<void> syncCurrentDrive() async {
    final state = this.state;
    if (state is DriveDetailLoadUnsynced) {
      final driveId = state.drive.id;
      final rootFolderId = state.drive.rootFolderId;

      _isExplicitSync = true;
      final bool synced;
      try {
        emit(DriveDetailLoadInProgress());
        // Background, not because nobody asked - they pressed Sync Now - but
        // because the panel they pressed it from already shows the phase, the
        // progress and the elapsed time. A modal over it is the same report
        // twice, and takes away the app while it does it.
        synced = await _syncCubit.startSyncForDrive(
          driveId: driveId,
          deepSync: false,
        );
      } finally {
        _isExplicitSync = false;
      }

      // Nothing ran, so there is nothing to report. Everything below reads the
      // drive and reports what the sync found; on a refusal - one sync at a
      // time, no queue - it would find the drive exactly as empty as it was
      // and emit `syncFoundNothing`, telling the user a sync looked when none
      // ever started. The answer comes from the sync itself rather than from
      // guessing at its state afterwards, so a future caller cannot lose it.
      if (!synced) {
        // Back to exactly the panel the press came from, flags and all -
        // unless the screen has moved on, in which case restoring this drive's
        // panel would put it over another drive's.
        if (isClosed || _driveId != driveId) return;

        emit(state);
        return;
      }

      // Still this drive, and still the loading state this call put up. Any
      // other state means something else owns the screen now and this result
      // is not its business.
      if (isClosed || _driveId != driveId) return;

      if (this.state is! DriveDetailLoadInProgress) {
        return;
      }

      // Only a sync that ran to the end may have its findings reported. Every
      // other ending - cancelled, failed outright, finished with failed drives
      // - leaves the drive exactly as empty as it was, and reporting that as
      // "the sync looked and found nothing" is a confident, false explanation
      // for a network read that did not happen.
      //
      // Asked of the state rather than enumerated here: a guard naming
      // `SyncCancelled` and `SyncFailure` let `SyncCompleteWithErrors` fall
      // straight through to `syncFoundNothing`, and the next state added
      // would have done the same. See [SyncState.isSuccessfulCompletion].
      if (!_syncCubit.state.isSuccessfulCompletion) {
        // Back to the panel the press came from. Returning without emitting
        // strands the explorer on "Opening Drive X" forever - nothing else
        // emits, and neither the following `SyncIdle` nor a later Resync
        // rescues a state nothing is waiting on.
        emit(state);
        return;
      }

      // Verify the drive was actually synced by checking lastBlockHeight
      final drive =
          await _driveDao.driveById(driveId: driveId).getSingleOrNull();

      // Re-check state after the async operation
      if (isClosed || _driveId != driveId) return;

      if (drive == null) {
        emit(DriveDetailLoadNotFound());
        return;
      }

      final hasRootFolderMetadata = await _hasRootFolderMetadata(drive);

      if (isClosed || _driveId != driveId) return;

      if (!hasRootFolderMetadata) {
        // The sync ran, finished, and the drive's root metadata still is not
        // there. Re-emitting the plain unsynced card would put the user back
        // on the screen they just pressed Sync Now on, with nothing to say the
        // press did anything - so the card is told a sync has already looked.
        emit(DriveDetailLoadUnsynced(drive: drive, syncFoundNothing: true));
        return;
      }

      // Sync completed successfully and drive is verified synced
      openFolder(folderId: rootFolderId);
    }
  }

  /// Shows the drive info panel for an unsynced drive.
  void selectDriveInfoForUnsyncedDrive(ArDriveDataTableItem driveItem) {
    final state = this.state;
    if (state is DriveDetailLoadUnsynced) {
      emit(state.copyWith(
        showDriveInfo: true,
        selectedItem: driveItem,
      ));
    }
  }

  /// Hides the drive info panel for an unsynced drive.
  void closeDriveInfoForUnsyncedDrive() {
    final state = this.state;
    if (state is DriveDetailLoadUnsynced) {
      emit(DriveDetailLoadUnsynced(
        drive: state.drive,
        showDriveInfo: false,
        selectedItem: null,
      ));
    }
  }

  /// The drive's root folder row is missing, so the explorer cannot mount it.
  ///
  /// `DriveDao._rootFolderPlaceholder` makes this structurally unreachable for
  /// any drive written since, and heals already-affected drives on their next
  /// sync. It is still handled rather than asserted away: whichever way a drive
  /// gets here, it has to land somewhere the user can act from.
  ///
  /// Both outcomes are states a later sync recovers from on its own -
  /// [DriveDetailLoadUnsynced] is re-checked by [_onSyncCompleted], and it
  /// renders the drive with whatever did sync. The previous
  /// [DriveInitialLoading] was a dead end: no retry, no action, and nothing
  /// that re-triggers it.
  Future<void> _handleFolderNotFound(String driveId) async {
    final drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();
    // The drive can be switched out from under this query. Emitting after that
    // would put the previous drive's state on the new drive's screen.
    if (isClosed || _driveId != driveId) return;

    if (drive == null) {
      emit(DriveDetailLoadNotFound());
      return;
    }

    emit(DriveDetailLoadUnsynced(drive: drive));
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    _syncSubscription?.cancel();
    _allImagesOfCurrentFolder = null;
    return super.close();
  }
}
