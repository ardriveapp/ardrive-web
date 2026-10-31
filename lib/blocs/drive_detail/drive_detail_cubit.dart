import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_detail/utils/breadcrumb_builder.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
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

  /// The drive row last drawn, for the same reason. A rename or a hide
  /// changes only this, and the folder contents arrive identical.
  Drive? _lastDrive;

  /// The drive this screen is waiting to open, if any: for its root revision,
  /// or for the first of its contents while a sync is still reading it.
  ///
  /// Only a sync writing that drive can end the wait, so a sync that ends
  /// without doing it has to be noticed - see [_recoverIfStillWaiting].
  String? _awaitingRootRevisionFor;

  /// Whether each drive's root folder came from the network rather than from
  /// this device: the difference between a drive a sync is reading for the
  /// first time and one just made here, which both have a block height of 0.
  ///
  /// Decided the first time this screen shows the drive with an empty folder,
  /// and kept: a sync rewrites a new drive's root as confirmed when it reads
  /// it back, and the drive on screen must not turn into a loading panel
  /// because of it. A root not there at all is from the network by
  /// definition: it has not arrived yet.
  final _rootFromNetwork = <String, bool>{};
  bool _isExplicitSync = false;

  /// Bumped by every [openFolder]. Cancelling `_folderSubscription` does not
  /// cancel a callback that already began awaiting, so an in-flight load can
  /// still emit after the user has navigated somewhere else in the same drive
  /// - where the `_driveId` checks cannot see it, because the drive did not
  /// change. Callbacks capture this and drop their result if it moved on.
  int _folderLoadGeneration = 0;
  final _defaultAvailableRowsPerPage = [25, 50, 75, 100];

  /// The page sizes the file table offers.
  static const rowsPerPageOptions = [25, 50, 100];
  static const _rowsPerPageKey = 'drive_detail_rows_per_page';

  int _rowsPerPage = rowsPerPageOptions.first;

  /// The first row on screen in each folder visited this session, and how far
  /// down its page the list was scrolled.
  ///
  /// The table is rebuilt whenever its folder is left and whenever something
  /// refreshes it in place - a rename, a hide, an upload, a sync finishing -
  /// and a new table starts on page 1 at the top. Kept here, so the reader is
  /// put back where they were rather than sent to the start each time. A row
  /// rather than a page, so a change of page size keeps the same rows in view.
  final _firstRowByFolder = <String, int>{};
  final _scrollOffsetByFolder = <String, double>{};

  /// The order picked from a column header in each folder, for the same
  /// reason: a sort lives in the table, and an upload or a rename rebuilt the
  /// table and dropped it.
  final _sortByFolder = <String, ({int column, TableSort order})>{};

  /// Set when a folder is opened to show one item in it, such as a search
  /// result: the next state asks the table to open on that item's page.
  bool _revealSelectedItem = false;

  List<ArDriveDataTableItem> _selectedItems = [];
  List<ArDriveDataTableItem> get selectedItems => _selectedItems;

  List<FileDataTableItem>? _allImagesOfCurrentFolder;

  bool _forceDisableMultiselect = false;

  bool _refreshSelectedItem = false;

  /// The folder a link named, while it is not on this device yet. Kept until
  /// it opens, the reader opens another folder, or another drive is opened -
  /// so a second [changeDrive] for the same drive cannot drop it.
  ({String driveId, String folderId})? _linkedFolder;

  /// Waits for [_linkedFolder] to be written by the sync reading its drive.
  StreamSubscription? _linkedFolderWatch;

  /// Drops [_linkedFolder] as soon as the reader opens any other folder, even
  /// one they have left again by the time the linked folder lands.
  StreamSubscription? _readerMovedWatch;

  /// Counts [followLink] calls, so a lookup for an older link that finishes
  /// after a newer one cannot open its folder over the newer one's.
  int _followedLinks = 0;

  /// On a publication, the folder the publication was published at: breadcrumbs
  /// start there rather than at the drive's root (docs/PUBLICATIONS.md).
  final String? publicationScopeRootFolderId;

  DriveDetailCubit({
    required String driveId,
    String? initialFolderId,

    /// The item to pick out once [initialFolderId] has opened.
    ///
    /// For a search result reached from the drives list. The explorer's own
    /// search calls `openFolder(selectedItemId: ...)` on a cubit that already
    /// exists; there is no such cubit to call when the drives list is what is on
    /// screen, so the file to highlight has to arrive with the drive.
    String? initialSelectedItemId,
    required ProfileCubit profileCubit,
    required DriveDao driveDao,
    required ConfigService configService,
    required ActivityTracker activityTracker,
    required ArDriveAuth auth,
    required BreadcrumbBuilder breadcrumbBuilder,
    required SyncCubit syncCubit,
    required DriveRepository driveRepository,
    this.publicationScopeRootFolderId,
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
      Future.microtask(() async {
        final found = await _driveDao
            .folderById(folderId: initialFolderId)
            .getSingleOrNull();
        // Folder IDs are only unique within a drive: a link that pairs this
        // drive with another drive's folder names nothing here.
        final folder = found?.driveId == driveId ? found : null;

        // Abort if user switched drives during the async operation
        if (_driveId != driveId) return;

        // A link to a folder this device does not have yet. If its drive is
        // not here either, the drive gets attached and synced first, and then
        // opened through [changeDrive] - which has to open this folder, not
        // the root.
        if (folder == null) {
          _linkedFolder = (driveId: driveId, folderId: initialFolderId);
        }

        // Open the root folder if the deep-linked folder could not be found.
        // The item is only meaningful inside the folder that was asked for: if
        // that folder is gone, so is any claim about what was in it.
        openFolder(
          folderId: folder?.id,
          selectedItemId: folder == null ? null : initialSelectedItemId,
        );
        // The empty string here is required to open the root folder

        if (folder != null) {
          return;
        }

        // The drive is here and the folder is not: a sync of the drive has
        // not reached it yet. [changeDrive] is not coming for a drive that is
        // already open, so wait for the folder here.
        final drive =
            await _driveDao.driveById(driveId: driveId).getSingleOrNull();

        if (isClosed || _driveId != driveId || drive == null) {
          return;
        }

        if (_linkedFolder?.folderId == initialFolderId) {
          _openLinkedFolderWhenItLands(
            driveId: driveId,
            folderId: initialFolderId,
            rootFolderId: drive.rootFolderId,
          );
        }
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

  /// Whether an empty folder in [drive] may only be empty *so far*.
  ///
  /// Sync saves a drive's history oldest first, one batch at a time, so a
  /// folder lands before anything in it. While a sync is reading a drive for
  /// the first time on this device, an empty folder says nothing about what
  /// the drive holds - and showing the empty-drive card then is what made a
  /// full drive flash "Your brand new drive!" before its files appeared.
  ///
  /// Only for a drive whose root came from the network ([_rootFromNetwork]),
  /// never one just made on this device. Never for one walked before (its
  /// block height has advanced), whose emptiness was read, not assumed. And
  /// only while a sync is walking it: not while the drive list loads, which
  /// reads no folder.
  bool contentsMayStillArrive(Drive drive) {
    if (_rootFromNetwork[drive.id] != true ||
        (drive.lastBlockHeight ?? 0) > 0) {
      return false;
    }

    return _syncCubit.state is SyncInProgress &&
        SyncCubit.syncTouchesDrive(
          state: _syncCubit.state,
          syncingDriveId: _syncCubit.syncingDriveId,
          completedDriveIds: _syncCubit.completedDriveIds,
          runDriveIds: _syncCubit.syncingDriveIds,
          driveId: drive.id,
        );
  }

  /// Whether [drive]'s root folder was read from the network, or is not here
  /// yet. Sync records what it reads as confirmed; a drive made on this device
  /// writes its own root as pending, until its upload is confirmed. A root
  /// with no transaction row at all was not written here, since a local
  /// write adds both in one transaction.
  Future<bool> _rootIsFromNetwork(Drive drive) async {
    final root = await _driveDao
        .latestFolderRevisionByFolderId(
          driveId: drive.id,
          folderId: drive.rootFolderId,
        )
        .getSingleOrNull();

    if (root == null) {
      return true;
    }

    final transaction = await (_driveDao.select(_driveDao.networkTransactions)
          ..where((t) => t.id.equals(root.metadataTxId)))
        .getSingleOrNull();

    return transaction == null ||
        transaction.status == TransactionStatus.confirmed;
  }

  /// Ends a wait for a root revision that is never going to arrive.
  ///
  /// The panel waits rather than claiming "Drive Not Synced" while a sync is
  /// walking that drive, because the revision has probably not landed *yet*.
  /// The wait is ended by the tick that writes it - and a run that fails, is
  /// cancelled, or fails on this drive in particular writes nothing at all, so
  /// no tick comes and the panel sits on "Opening..." for good.
  ///
  /// So a run reaching any terminal state re-reads the folder once. If the
  /// revision did arrive, this draws it; if it did not, the same branch now
  /// finds no sync in progress and says "Drive Not Synced", which is true and
  /// offers a way out.
  Future<void> _recoverIfStillWaiting() async {
    final waitingFor = _awaitingRootRevisionFor;

    if (waitingFor == null || isClosed) {
      return;
    }

    _awaitingRootRevisionFor = null;

    if (waitingFor != _driveId || state is! DriveDetailLoadInProgress) {
      return;
    }

    final drive =
        await _driveDao.driveById(driveId: waitingFor).getSingleOrNull();

    if (isClosed || drive == null || waitingFor != _driveId) {
      return;
    }

    openFolder(folderId: drive.rootFolderId, otherDriveId: waitingFor);
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
        _recoverIfStillWaiting();
        _refreshAfterDroppedRedraws();
      }

      // The sync moving on can end a first read without writing a row, and
      // so without a tick to redraw the folder: an empty folder left saying
      // it is still being read after the reading has stopped.
      final current = state;
      if (current is DriveDetailLoadSuccess) {
        final stillArriving = contentsMayStillArrive(current.currentDrive);

        if (stillArriving != current.contentsStillArriving) {
          emit(current.copyWith(contentsStillArriving: stillArriving));
        }
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
      _detailsOpen = false;
    } else {
      // Enable refresh so the subscription callback updates the drive info
      _refreshSelectedItem = true;
    }

    _driveId = driveId;

    // One shot: the folder a link named is opened the first time its drive
    // is, and after that the drive opens at its root like any other. It is
    // only let go once it has been dealt with: attaching a drive can bring
    // this call more than once, and the second must not find it gone.
    final linkedFolder =
        _linkedFolder?.driveId == driveId ? _linkedFolder : null;

    if (linkedFolder == null) {
      _forgetLinkedFolder();
    }

    final folder = linkedFolder == null
        ? null
        : await _driveDao
            .folderById(folderId: linkedFolder.folderId)
            .getSingleOrNull();

    if (isClosed || _driveId != driveId) {
      return;
    }

    if (folder != null && folder.driveId == driveId) {
      _forgetLinkedFolder();
      openFolder(folderId: folder.id);
      return;
    }

    final rootFolderId = drive.rootFolderId;
    openFolder(folderId: rootFolderId);

    // The drive opens as soon as its row is written, while the sync that
    // attached it is still reading its folders - so a linked folder is
    // usually not there yet.
    if (linkedFolder != null && _linkedFolder == linkedFolder) {
      _openLinkedFolderWhenItLands(
        driveId: driveId,
        folderId: linkedFolder.folderId,
        rootFolderId: rootFolderId,
      );
    }
  }

  /// Opens the linked folder when the sync writes it, unless the reader has
  /// opened another folder in the meantime.
  void _openLinkedFolderWhenItLands({
    required String driveId,
    required String folderId,
    required String rootFolderId,
  }) {
    _forgetLinkedFolder();
    _linkedFolder = (driveId: driveId, folderId: folderId);

    // Any folder but the root, even briefly: a reader who looked around and
    // came back to the root chose to be there.
    _readerMovedWatch = stream.listen((state) {
      if (state is DriveDetailLoadSuccess &&
          state.folderInView.folder.id != rootFolderId) {
        _forgetLinkedFolder();
      }
    });

    _linkedFolderWatch = _driveDao
        .folderById(folderId: folderId)
        .watchSingleOrNull()
        .where((folder) => folder?.driveId == driveId)
        .take(1)
        .listen((folder) {
      _forgetLinkedFolder();

      if (isClosed || _driveId != driveId) {
        return;
      }

      openFolder(folderId: folder!.id);
    });
  }

  /// A drive or folder link followed in a tab where this explorer is already
  /// open: pasted into the address bar, or reached with back and forward.
  ///
  /// The link was only ever read when the explorer was built, so a tab that
  /// already had it ignored every later one and the address bar snapped back
  /// to the folder on screen.
  ///
  /// For the drive on screen this opens the folder, or the root for a drive
  /// link, waiting for a folder its sync has not written yet. For any other
  /// drive it only holds the folder: selecting that drive is the caller's,
  /// and [changeDrive] opens the folder when it does.
  Future<void> followLink({required String driveId, String? folderId}) async {
    _forgetLinkedFolder();
    final link = ++_followedLinks;

    final current = state;
    final showingThisDrive = driveId == _driveId &&
        current is DriveDetailLoadSuccess &&
        current.currentDrive.id == driveId;

    if (!showingThisDrive) {
      if (folderId == null) {
        return;
      }

      final linkedFolder = (driveId: driveId, folderId: folderId);
      _linkedFolder = linkedFolder;

      // Another drive: its changeDrive is still to come and opens the folder.
      if (driveId != _driveId) {
        return;
      }

      // This drive, but not showing a folder: still opening, or waiting for
      // its root. No changeDrive will come, so wait for the folder here.
      final drive =
          await _driveDao.driveById(driveId: driveId).getSingleOrNull();

      // A changeDrive already under way may have taken the folder over.
      if (isClosed ||
          link != _followedLinks ||
          _driveId != driveId ||
          drive == null ||
          _linkedFolder != linkedFolder) {
        return;
      }

      _openLinkedFolderWhenItLands(
        driveId: driveId,
        folderId: folderId,
        rootFolderId: drive.rootFolderId,
      );
      return;
    }

    final rootFolderId = current.currentDrive.rootFolderId;
    final targetId = folderId ?? rootFolderId;

    if (targetId == current.folderInView.folder.id) {
      return;
    }

    final folder =
        await _driveDao.folderById(folderId: targetId).getSingleOrNull();

    if (isClosed || link != _followedLinks || _driveId != driveId) {
      return;
    }

    if (folder != null && folder.driveId == driveId) {
      openFolder(folderId: targetId);
      return;
    }

    // Not on this device yet: the root, as for a visitor's link, and then the
    // folder when the sync writes it.
    openFolder(folderId: rootFolderId);
    _openLinkedFolderWhenItLands(
      driveId: driveId,
      folderId: targetId,
      rootFolderId: rootFolderId,
    );
  }

  void _forgetLinkedFolder() {
    _linkedFolder = null;
    _linkedFolderWatch?.cancel();
    _linkedFolderWatch = null;
    _readerMovedWatch?.cancel();
    _readerMovedWatch = null;
  }

  Future<void> openFolder({
    String? folderId,
    String? otherDriveId,
    String? selectedItemId,
    DriveOrder contentOrderBy = DriveOrder.name,
    OrderingMode contentOrderingMode = OrderingMode.asc,
  }) async {
    // "The root" on a publication is the folder it was published at, never
    // the drive's own root above it.
    folderId ??= otherDriveId == null ? publicationScopeRootFolderId : null;

    // Claimed before the first await, so anything already in flight for a
    // previous folder is stale from here on even when the drive is unchanged.
    final loadGeneration = ++_folderLoadGeneration;

    // Whether [selectedItemId] has been found and shown. Once it has, later
    // ticks of this folder leave the selection to the reader.
    var revealedSelectedItem = false;

    // A different folder takes the details panel's item with it: what was
    // picked out of the last folder is not in this one, and the panel kept
    // describing it while the reader moved on. The drive info panel is about
    // the drive, which has not changed, and a search result names the item it
    // wants shown. Re-opening the folder in view - a sort, a refresh - is not
    // moving on, so the reader's pick survives that.
    final inView = state;
    if (selectedItemId == null &&
        _selectedItem is! DriveDataItem &&
        inView is DriveDetailLoadSuccess &&
        (folderId ?? inView.currentDrive.rootFolderId) !=
            inView.folderInView.folder.id) {
      _selectedItem = null;
      _detailsOpen = false;
    }

    // A new folder redraws immediately whatever the last one did: the throttle
    // exists to stop a folder flickering as it fills, not to delay one being
    // opened.
    _lastFolderRedraw = null;
    _droppedFolderRedraw = false;
    _lastFolderContents = null;
    _lastDrive = null;

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
          // FolderWithContents is Equatable and Drive is a Drift data class,
          // so this is exact rather than a heuristic: skip only when neither
          // has changed at all. Unlike the interval below it, this never
          // delays anything - a tick that carries a real change is never the
          // one dropped here.
          //
          // The drive is compared as well as the contents. Rename Drive writes
          // only the drive row, so comparing contents alone dropped the one
          // tick carrying the new name, and the breadcrumb kept the old one.
          //
          // The cost is a redraw for drive-row writes nobody sees: the
          // watermark at the end of each drive's sync, and, for a private
          // drive, the key re-encrypted with a fresh nonce when
          // `updateUserDrives` runs at the start of a sync. A few per sync,
          // not one per batch. Comparing only the fields this page shows
          // would save them, at the price of a list to keep in step with the
          // page.
          if (_lastFolderContents == folderContents &&
              _lastDrive == drive &&
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
          //
          // Only once the folder is on screen. While the loading panel is
          // still up, the tick being dropped could be the one that ends it.
          if (this.state is DriveDetailLoadSuccess &&
              SyncCubit.syncTouchesDrive(
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
          _lastDrive = drive;

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

          if (driveIsEmpty &&
              (drive.lastBlockHeight ?? 0) == 0 &&
              !_rootFromNetwork.containsKey(driveId)) {
            _rootFromNetwork[driveId] = await _rootIsFromNetwork(drive);

            if (isClosed ||
                driveId != _driveId ||
                loadGeneration != _folderLoadGeneration) {
              return;
            }
          }

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
              _rootFromNetwork[driveId] = true;

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
                  // Remembered, because waiting here is only safe if something
                  // is going to end the wait. The tick that would resolve this
                  // arrives only if the sync writes a row for this drive - and
                  // a sync that fails, is cancelled, or fails on this drive
                  // specifically writes nothing, so the stream never fires
                  // again and the panel says "Opening..." until the reader
                  // navigates away and back.
                  //
                  // Before reading stopped waiting for the sync this could not
                  // happen: the check always ran after the sync had settled.
                  _awaitingRootRevisionFor = driveId;
                  emit(DriveDetailLoadInProgress());
                }

                return;
              }

              _awaitingRootRevisionFor = null;

              emit(DriveDetailLoadUnsynced(drive: drive));
              return;
            }

            // The root revision is in, but on a first walk it lands before
            // anything inside it, so the drive stays on the loading panel
            // until its first contents do. Ended by the tick that writes them,
            // or, for a drive that really is empty, by the sync finishing.
            if (this.state is! DriveDetailLoadSuccess &&
                contentsMayStillArrive(drive)) {
              _awaitingRootRevisionFor = driveId;

              if (this.state is! DriveDetailLoadInProgress) {
                emit(DriveDetailLoadInProgress());
              }

              return;
            }
          }

          _awaitingRootRevisionFor = null;

          final currentFolderContents = parseEntitiesToDatatableItem(
            folder: folderContents,
            isOwner: isDriveOwner(_auth, drive.ownerAddress),
          );

          // Only for the first draw of the folder: later ticks are the folder
          // changing under the reader, who may have moved on from the item.
          var revealSelectedItem = false;

          if (selectedItemId != null && !revealedSelectedItem) {
            // `firstWhere` without `orElse` throws when it finds nothing, and
            // there are ordinary reasons for it to find nothing here: the file
            // was moved or deleted between the search and the tap, or hidden
            // items are being filtered out. Failing to highlight a row is a
            // disappointment; throwing out of a folder load is a broken screen.
            _selectedItem = currentFolderContents
                .where((element) => element.id == selectedItemId)
                .firstOrNull;

            // Not found can mean not synced yet, so a later tick may still
            // find it.
            if (_selectedItem != null) {
              revealedSelectedItem = true;
              revealSelectedItem = true;
              _revealSelectedItem = true;
              // An item asked for by name - a search result, a link - is
              // shown, not just picked out.
              _detailsOpen = true;
            }
          }

          final driveHasLicensedFiles = await _driveHasLicensedFiles(driveId);

          final List<BreadCrumbRowInfo> pathSegments =
              await _breadcrumbBuilder.buildForFolder(
            folderId: folderContents.folder.id,
            rootFolderId: publicationScopeRootFolderId ?? drive.rootFolderId,
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
                rowsPerPage: _rowsPerPage,
                availableRowsPerPage: availableRowsPerPage,
                currentFolderContents: currentFolderContents,
                pathSegments: pathSegments,
                driveIsEmpty: driveIsEmpty,
                contentsStillArriving: contentsMayStillArrive(drive),
                driveHasLicensedFiles: driveHasLicensedFiles,
                showSelectedItemDetails: _showsDetails,
                revealSelectedItem: _revealSelectedItem,
                // The table is kept when the folder is unchanged, so one
                // already on screen has to be rebuilt to go to the item.
                forceRebuildKey: revealSelectedItem ? UniqueKey() : null,
              ),
            );
          } else {
            final columnsVisibility = await getTableColumnVisibility();
            _rowsPerPage = await _storedRowsPerPage();

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
                rowsPerPage: _rowsPerPage,
                availableRowsPerPage: availableRowsPerPage,
                driveIsEmpty: driveIsEmpty,
                contentsStillArriving: contentsMayStillArrive(drive),
                multiselect: false,
                currentFolderContents: currentFolderContents,
                columnVisibility: columnsVisibility,
                driveHasLicensedFiles: driveHasLicensedFiles,
                showSelectedItemDetails: _showsDetails,
                revealSelectedItem: _revealSelectedItem,
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

    return PublicationMode.isOn
        ? items.where(isShownInPublication).toList()
        : items;
  }

  /// What a publication shows (docs/PUBLICATIONS.md, "Never shown"): not
  /// hidden items, whatever a visitor's own preferences say, not ghost
  /// folders, whose metadata the snapshot never had, and not uploads that
  /// failed or were still pending when the snapshot was made. Filtered here,
  /// where the folder becomes items, so the table, its counts, image
  /// navigation and selection all see the same list.
  @visibleForTesting
  static bool isShownInPublication(ArDriveDataTableItem item) {
    if (item.isHidden) return false;
    if (item is FolderDataTableItem && item.isGhostFolder) return false;
    final status = item.fileStatusFromTransactions;
    return status != TransactionStatus.failed &&
        status != TransactionStatus.pending;
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

  /// Makes [item] the selected item.
  ///
  /// [openDetails] opens the details panel on it, which is what every caller
  /// but a click wants: More info, a preview's next and previous, a search
  /// result. A click passes false - Google Drive's model - and only selects:
  /// the panel, if it is already open, follows the selection, and if it is
  /// closed it stays closed.
  Future<void> selectDataItem(
    ArDriveDataTableItem item, {
    bool openSelectedPage = false,
    bool openDetails = true,
  }) async {
    var state = this.state as DriveDetailLoadSuccess;

    if (state.currentDrive.isPublic && item is FileDataTableItem) {
      final dataTxId = item.dataTxId;
      state = state.copyWith(
          selectedFilePreviewUrl:
              '${_configService.config.arweaveGatewayForDataRequest.url}/$dataTxId');
    }

    _selectedItem = item;

    if (openDetails) {
      _detailsOpen = true;
    }

    if (openSelectedPage) {
      _revealSelectedItem = true;
    }

    emit(
      state.copyWith(
        selectedItem: item,
        showSelectedItemDetails: _detailsOpen,
        revealSelectedItem: openSelectedPage ? true : null,
        forceRebuildKey: openSelectedPage ? UniqueKey() : null,
      ),
    );
  }

  /// The page the file table last showed in [folderId], if it has been
  /// visited this session.
  int? pageForFolder(String folderId) {
    final firstRow = _firstRowByFolder[folderId];
    return firstRow == null ? null : firstRow ~/ _rowsPerPage;
  }

  /// How far down that page the list was scrolled.
  double? scrollOffsetForFolder(String folderId) =>
      _scrollOffsetByFolder[folderId];

  /// The file table moved to [page] in [folderId].
  void rememberPage(String folderId, int page) {
    final firstRow = page * _rowsPerPage;

    if (_firstRowByFolder[folderId] != firstRow) {
      _firstRowByFolder[folderId] = firstRow;
      // A new page is shown from its top.
      _scrollOffsetByFolder.remove(folderId);
    }

    // The table reports the page it opened on when asked to show an item, so
    // this is also where that request is known to be done.
    if (_revealSelectedItem) {
      _revealSelectedItem = false;
      final state = this.state;
      if (state is DriveDetailLoadSuccess && !isClosed) {
        emit(state.copyWith(revealSelectedItem: false));
      }
    }
  }

  /// The column sort picked in [folderId], if one has been this session.
  ({int column, TableSort order})? sortForFolder(String folderId) =>
      _sortByFolder[folderId];

  /// A column sort picked from the file table's header in [folderId].
  void rememberSort(String folderId, int column, TableSort order) {
    _sortByFolder[folderId] = (column: column, order: order);
  }

  void rememberScrollOffset(String folderId, double offset) {
    _scrollOffsetByFolder[folderId] = offset;
  }

  /// A page size chosen in the file table, kept on this device.
  Future<void> setRowsPerPage(int rowsPerPage) async {
    if (rowsPerPage == _rowsPerPage) {
      return;
    }

    _rowsPerPage = rowsPerPage;

    final state = this.state;
    if (state is DriveDetailLoadSuccess && !isClosed) {
      emit(state.copyWith(rowsPerPage: rowsPerPage));
    }

    await (await _store()).putString(_rowsPerPageKey, '$rowsPerPage');
  }

  Future<int> _storedRowsPerPage() async {
    final stored =
        int.tryParse((await _store()).getString(_rowsPerPageKey) ?? '');

    return rowsPerPageOptions.contains(stored)
        ? stored!
        : rowsPerPageOptions.first;
  }

  /// Opens [item], as a double-click, a tap on a touch screen or Enter does,
  /// and as a click does on a publication: a folder is entered, and a file,
  /// which has no view of its own, is shown in the details panel with its
  /// preview.
  Future<void> openDataItem(ArDriveDataTableItem item) async {
    if (item is FolderDataTableItem) {
      await openFolder(folderId: item.id);
    } else {
      await selectDataItem(item);
    }
  }

  ArDriveDataTableItem? _selectedItem;

  ArDriveDataTableItem? get selectedItem => _selectedItem;

  /// Whether the details panel is open, which is not the same as there being
  /// a selected item: a click selects a row and leaves a closed panel closed.
  /// Kept here rather than read back from the state, because every redraw of
  /// the folder re-emits it.
  bool _detailsOpen = false;

  bool get _showsDetails => _selectedItem != null && _detailsOpen;

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

    _detailsOpen = !state.showSelectedItemDetails;

    emit(
      state.copyWith(showSelectedItemDetails: _detailsOpen),
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
    // Into the state as well as the store: the table is built from the state,
    // and a choice kept only in the store was undone by the next folder.
    final state = this.state;
    if (state is DriveDetailLoadSuccess && !isClosed) {
      emit(state.copyWith(
        columnVisibility: {
          ...state.columnVisibility,
          column.index: column.isVisible,
        },
      ));
    }

    (await _store()).putBool(
      'drive_detail_column_${column.index}',
      column.isVisible,
    );
  }

  /// The column the explorer shows by default only when the drive has a
  /// licensed file. See [DriveDetailLoadSuccess.driveHasLicensedFiles].
  static const licenseColumnIndex = 4;

  Future<Map<int, bool>> getTableColumnVisibility() async {
    final columnVisibility = <int, bool>{};

    for (int i = 0; i < 5; i++) {
      final isVisible = (await _store()).getBool(
        'drive_detail_column_$i',
      );

      if (isVisible != null) {
        columnVisibility[i] = isVisible;
      } else if (i != licenseColumnIndex) {
        // License is left out when the reader never chose: its default
        // depends on the drive, so the table decides it from
        // [DriveDetailLoadSuccess.driveHasLicensedFiles].
        columnVisibility[i] = true;
      }
    }

    return columnVisibility;
  }

  /// Whether the License column is shown: the reader's choice when there is
  /// one, otherwise whether anything in the drive is licensed.
  static bool showsLicenseColumn({
    required Map<int, bool> columnVisibility,
    required bool driveHasLicensedFiles,
  }) =>
      columnVisibility[licenseColumnIndex] ?? driveHasLicensedFiles;

  /// Read for every load, so a license added in this drive brings the column
  /// in. Whether to offer a column is not worth failing a folder over, so a
  /// read that fails leaves it at its default, hidden.
  Future<bool> _driveHasLicensedFiles(String driveId) async {
    try {
      return await _driveDao.driveHasLicensedFiles(driveId);
    } catch (e) {
      logger.w('Could not read whether drive $driveId has licensed files: $e');
      return false;
    }
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

    // The same gate the folder read applies when it finds no root revision:
    // a drive a sync is writing right now has simply not got its root folder
    // *yet*. A drive opened a moment ago from the sign-in screen arrives here
    // on its first tick, before the sync it started has written anything, and
    // "Drive not synced" with a Sync button flashed over the files that were
    // seconds away. Waiting on the loading panel is ended by the write
    // itself, or by [_recoverIfStillWaiting] if the sync ends without one.
    if (SyncCubit.syncTouchesDrive(
      state: _syncCubit.state,
      syncingDriveId: _syncCubit.syncingDriveId,
      completedDriveIds: _syncCubit.completedDriveIds,
      runDriveIds: _syncCubit.syncingDriveIds,
      driveId: driveId,
    )) {
      _awaitingRootRevisionFor = driveId;

      if (state is! DriveDetailLoadInProgress) {
        emit(DriveDetailLoadInProgress());
      }

      return;
    }

    emit(DriveDetailLoadUnsynced(drive: drive));
  }

  @override
  Future<void> close() {
    _folderSubscription?.cancel();
    _forgetLinkedFolder();
    _syncSubscription?.cancel();
    _allImagesOfCurrentFolder = null;
    return super.close();
  }
}
