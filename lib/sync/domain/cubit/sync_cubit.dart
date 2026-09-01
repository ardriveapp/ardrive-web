import 'dart:async';
import 'dart:math';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/constants.dart';
import 'package:ardrive/sync/domain/ghost_folder.dart';
import 'package:ardrive/sync/domain/repositories/sync_repository.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/domain/sync_run.dart';
import 'package:ardrive/sync/domain/sync_trigger.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Re-exported so every surface that already imports this cubit keeps seeing
/// [SyncTrigger] - it moved to its own file because the persisted sync history
/// records it and must not depend on the cubit.
export 'package:ardrive/sync/domain/sync_trigger.dart';

part 'sync_state.dart';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

/// The [SyncCubit] periodically syncs the user's owned and attached drives and their contents.
/// It also checks the status of unconfirmed transactions made by revisions.
class SyncCubit extends Cubit<SyncState> {
  final ProfileCubit _profileCubit;
  final ActivityCubit _activityCubit;
  final PromptToSnapshotBloc _promptToSnapshotBloc;
  final TabVisibilitySingleton _tabVisibility;
  final ConfigService _configService;
  final SyncRepository _syncRepository;
  final UserPreferencesRepository _userPreferencesRepository;

  StreamSubscription? _restartOnFocusStreamSubscription;
  StreamSubscription? _restartArConnectOnFocusStreamSubscription;
  StreamSubscription? _syncSub;
  StreamSubscription? _arconnectSyncSub;
  final StreamController<SyncProgress> syncProgressController =
      StreamController<SyncProgress>.broadcast();
  DateTime? _lastSync;
  DateTime _initSync = DateTime.now();

  String? _syncingDriveId;

  /// The single drive a running sync covers, or null.
  ///
  /// Null means two different things and the state says which: no sync is
  /// running, or the running sync covers every drive. A surface that lists
  /// drives needs this to say "Syncing..." on the row it is true of instead of
  /// on all of them - [SyncProgress] carries a drive *name* for the modal to
  /// print, and names are not identity.
  String? get syncingDriveId => _syncingDriveId;

  /// Exposed so every surface counting a wait counts from the same instant -
  /// see `SyncElapsedTime`.
  DateTime get syncStartTime => _initSync;

  SyncProgress _syncProgress = SyncProgress.initial();
  SyncCancellationToken? _currentSyncToken;

  /// Publishes the current progress, if there is still anything to publish to.
  ///
  /// [close] cancels the running sync and closes this controller, but the sync
  /// itself unwinds afterwards - the repository only notices the cancellation
  /// at its next checkpoint, which can be a network round trip away. Adding to
  /// a closed controller throws, and that throw would surface as an unhandled
  /// asynchronous error from a cubit nothing owns any more.
  void _publishProgress() {
    if (syncProgressController.isClosed) return;

    syncProgressController.add(_syncProgress);
  }

  /// Emits, if this cubit is still open.
  ///
  /// Same reason as [_publishProgress]: a sync unwinding after [close] still
  /// runs its own terminal-state code, and `emit` on a closed cubit throws.
  void _emitIfOpen(SyncState state) {
    if (isClosed) return;

    emit(state);
  }

  Map<String, List<String>> _lastSyncSkippedEntityTxIdsByDrive = const {};

  /// Transaction ids of entities the most recent sync could not read, keyed by
  /// drive id. Retained on the cubit — not just on the terminal state — so it
  /// survives a plain [SyncIdle] completion, which is the common case when
  /// items are skipped but no drive outright fails.
  ///
  /// This is currently the only record that anything was dropped. A later pass
  /// renders it as "failed files"; persisting and retrying these across syncs
  /// is described in `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
  Map<String, List<String>> get lastSyncSkippedEntityTxIdsByDrive =>
      _lastSyncSkippedEntityTxIdsByDrive;

  int get lastSyncSkippedEntityCount =>
      _lastSyncSkippedEntityTxIdsByDrive.values
          .fold(0, (sum, txIds) => sum + txIds.length);

  void _captureSkippedEntities(SyncProgress progress) {
    _lastSyncSkippedEntityTxIdsByDrive = progress.skippedEntityTxIdsByDrive;
  }

  /// What the sync that just finished found, read straight off the progress it
  /// already reported. Nothing here is recounted: the repository owns these
  /// numbers, this only carries them out to the two surfaces that say so.
  /// Counts the results this cubit has reported, so each one is a state of its
  /// own. See [SyncComplete.sequence] for why a timestamp will not do.
  int _completedSyncCount = 0;

  SyncComplete _syncComplete(SyncTrigger trigger) => SyncComplete(
        entitiesSynced: _syncProgress.entitiesSynced,
        skippedEntityCount: _syncProgress.skippedEntityCount,
        isSingleDriveSync: _syncProgress.isSingleDriveSync,
        driveName: _syncProgress.driveName,
        trigger: trigger,
        completedAt: DateTime.now(),
        sequence: ++_completedSyncCount,
      );

  SyncCubit({
    required ProfileCubit profileCubit,
    required ActivityCubit activityCubit,
    required PromptToSnapshotBloc promptToSnapshotBloc,
    required TabVisibilitySingleton tabVisibility,
    required ConfigService configService,
    required ActivityTracker activityTracker,
    required SyncRepository syncRepository,
    required UserPreferencesRepository userPreferencesRepository,
  })  : _profileCubit = profileCubit,
        _activityCubit = activityCubit,
        _promptToSnapshotBloc = promptToSnapshotBloc,
        _configService = configService,
        _tabVisibility = tabVisibility,
        _syncRepository = syncRepository,
        _userPreferencesRepository = userPreferencesRepository,
        // Initialize with SyncLoadingDrives (not SyncIdle) to prevent race conditions
        // where DriveDetailCubit's waitCurrentSync() returns early before sync starts.
        super(SyncLoadingDrives()) {
    // Sync the user's drives on start and periodically.
    createSyncStream();
    restartSyncOnFocus();
    // Sync ArConnect
    createArConnectSyncStream();
    restartArConnectSyncOnFocus();
  }

  /// Waits for the current sync to finish.
  /// SyncLoadingDrives is treated as non-blocking (metadata-only loading).
  /// Whether a sync has finished, by whatever route it got there.
  ///
  /// The entry guard and the loop in [waitCurrentSync] have to agree on this.
  /// They did not: the guard let through every state but two, while the loop
  /// broke on five - so a wait that BEGAN while the cubit was already sitting
  /// in `SyncCompleteWithErrors`, `SyncFailure` or `SyncCancelled` blocked on
  /// an emission that had already happened and was never coming again.
  /// Whether the sync that was running is over, however it ended.
  ///
  /// Public because waiting for `SyncIdle` is not the same question and was
  /// getting the wrong answer: `SyncCompleteWithErrors` and `SyncFailure` are
  /// rests, not way-points, and neither is a `SyncIdle`. A listener that waited
  /// for one specifically - `SharingFileListener` did - waited forever the
  /// moment a single drive failed.
  ///
  /// [SyncWalletMismatch] is terminal too: nothing follows it.
  static bool syncHasFinished(SyncState state) =>
      state is SyncIdle ||
      state is SyncFailure ||
      state is SyncCancelled ||
      state is SyncCompleteWithErrors ||
      state is SyncWalletMismatch ||
      state is SyncLoadingDrives;

  Future<void> waitCurrentSync() async {
    if (syncHasFinished(state)) return;

    await for (final state in stream) {
      if (syncHasFinished(state)) break;
    }
  }

  /// Whether the drive list itself has been refreshed.
  ///
  /// A different question from [syncHasFinished], and deliberately so.
  /// `SyncLoadingDrives` counts as finished there because a folder open must
  /// not hang behind a metadata refresh - but that is exactly the state a
  /// login sync sits in while `updateUserDrives` is still running, so anything
  /// asking "does this user have drives?" gets its answer from an empty table
  /// nobody has filled in yet. `SyncInProgress` blocks too: a full sync
  /// refreshes the list on its way through, so a wait that returned during one
  /// would be reading the same half-written table.
  static bool _driveListRefreshHasFinished(SyncState state) =>
      state is! SyncLoadingDrives && state is! SyncInProgress;

  /// Waits for the drive list to have actually been looked at.
  ///
  /// For the one caller that needs it: the screen that would otherwise tell a
  /// user with drives that they have none. Everything else still waits on
  /// [waitCurrentSync], which stays non-blocking during a metadata refresh.
  Future<void> waitForDriveListRefresh() async {
    if (_driveListRefreshHasFinished(state)) return;

    await for (final state in stream) {
      if (_driveListRefreshHasFinished(state)) break;
    }
  }

  /// Whether the last thing this cubit did to the drive list failed.
  ///
  /// [SyncFailure] is the only terminal failure state - `onError` emits it and
  /// then `SyncIdle` in the same turn - so it means precisely "the drive-list
  /// refresh could not be done", which is what the explorer needs to know
  /// before it claims the user has no drives.
  bool get driveListRefreshFailed => state is SyncFailure;

  void createSyncStream() async {
    logger.d('Creating sync stream to periodically call sync automatically');

    // Note: Initial state is already SyncLoadingDrives (set in constructor)
    // to prevent race conditions with waitCurrentSync()

    // Check if syncAllDrivesOnLogin preference is enabled before initial sync.
    //
    // A local read that throws must not strand the app: the cubit starts in
    // SyncLoadingDrives, and anything waiting on the drive-list refresh waits
    // on leaving that state - so a throw here would pin the explorer on
    // "Loading your drives..." with nothing to end it. Falling back to the
    // shipped default keeps the login moving.
    bool syncAllDrivesOnLogin;
    try {
      syncAllDrivesOnLogin =
          (await _userPreferencesRepository.load()).syncAllDrivesOnLogin;
    } catch (e, stackTrace) {
      logger.e('Could not read preferences on login', e, stackTrace);
      syncAllDrivesOnLogin = false;
    }

    if (syncAllDrivesOnLogin) {
      // Start initial sync immediately without waiting for async operations.
      // Skip tab visibility check for initial sync because the user just logged in
      // (which requires wallet interaction, proving they're active). The wallet popup
      // may cause the browser to consider the tab unfocused momentarily.
      startSync(
        skipTabVisibilityCheck: true,
        trigger: SyncTrigger.background,
      );
    } else {
      logger.d('Skipping full sync: syncAllDrivesOnLogin is disabled');
      // Not awaited, exactly like the startSync above it: the periodic
      // subscription below must be created on the same beat it always was.
      _syncOnlyIfThereIsWork();
    }

    // Cancel any existing subscription before creating a new one
    await _syncSub?.cancel();

    _syncSub = Stream.periodic(
            Duration(seconds: _configService.config.autoSyncIntervalInSeconds))
        // Do not start another sync until the previous sync has completed.
        .map((value) {
      /// Only start sync if autoSync is enabled.
      if (_configService.config.autoSync) {
        // Nobody asked for this one either: it is a timer firing, so it has to
        // stay out of the way exactly like the sync on login.
        return Stream.fromFuture(
          startSync(trigger: SyncTrigger.background),
        );
      }
    }).listen((_) {
      logger.d('Listening to startSync periodic stream');
    });
  }

  /// The login path when the user is not syncing everything on start.
  ///
  /// Two things still have to happen. The drive list is refreshed either way -
  /// [syncMetadataOnly] is `updateUserDrives` and nothing more, so a drive that
  /// was created or renamed elsewhere still appears. Not syncing must not mean
  /// not noticing drives.
  ///
  /// Then, and only then, the one case where a full sync is still owed: an
  /// upload whose transaction has not been resolved yet. Nothing but a sync
  /// resolves it, so a sync that finishes work the user already started is the
  /// only one this path will run. It is a local read and makes no network
  /// request.
  ///
  /// Deliberately NOT "and sync when the database is empty". A first login
  /// with this setting off shows the drive list with no contents, and each
  /// drive opens on the "Drive Not Synced" card with its own Sync button -
  /// which is the honest outcome of turning the setting off, and an
  /// affordance that already exists. Syncing anyway overrode an explicit
  /// choice to protect the user from a state they had asked for.
  ///
  /// When we skip, the user is told nothing, and that is the point. Silence is
  /// the feature being asked for here: an unlock that says "not syncing" has
  /// simply moved the interruption rather than removed it, and it would be a
  /// notice about an absence of work, which is the least useful thing to
  /// report. The state the app is in is the ordinary idle one, and Resync sits
  /// in the top bar for anyone who wants a sync anyway. The case where the
  /// silence would be a lie - work outstanding - is the case that syncs.
  Future<void> _syncOnlyIfThereIsWork() async {
    await syncMetadataOnly();

    if (isClosed) return;

    bool thereIsWork;
    try {
      thereIsWork = await _syncRepository.hasPendingTransactions();
    } catch (e, stackTrace) {
      // A failed local read is not a reason to sync, and not a reason to fail
      // a login: the drive list is already refreshed and Resync still works.
      logger.e('Could not check whether a sync was owed', e, stackTrace);
      return;
    }

    if (isClosed || !thereIsWork) {
      logger.d('Nothing owed: leaving the login sync skipped');
      return;
    }

    logger.i('Syncing on login: transactions are still pending');

    startSync(
      skipTabVisibilityCheck: true,
      trigger: SyncTrigger.background,
    );
  }

  void restartSyncOnFocus() {
    _restartOnFocusStreamSubscription =
        _tabVisibility.onTabGetsFocused(_restartSync);
  }

  void _restartSync() {
    logger.d(
      'Attempting to create a sync subscription when the window regains focus.'
      ' Is Cubit active? ${!isClosed}',
    );

    if (_lastSync != null) {
      final syncInterval = _configService.config.autoSyncIntervalInSeconds;
      final minutesSinceLastSync =
          DateTime.now().difference(_lastSync!).inSeconds;
      final isTimerDurationReadyToSync = minutesSinceLastSync >= syncInterval;

      if (!isTimerDurationReadyToSync) {
        return;
      }
    }

    /// This delay is for don't abruptly open the modal when the user is back
    ///  to ArDrive browser tab
    Future.delayed(const Duration(seconds: 2)).then((value) {
      /// Only restart sync if autoSync is enabled.
      if (_configService.config.autoSync) createSyncStream();
    });
  }

  void createArConnectSyncStream() {
    _profileCubit.isCurrentProfileArConnect().then((isArConnect) {
      if (isArConnect) {
        _arconnectSyncSub?.cancel();
        _arconnectSyncSub = Stream.periodic(
                const Duration(minutes: kArConnectSyncTimerDuration))
            // Do not start another sync until the previous sync has completed.
            .map((value) {
          /// Only start sync if autoSync is enabled.
          if (_configService.config.autoSync) {
            return Stream.fromFuture(arconnectSync());
          }
        }).listen((_) {});
        arconnectSync();
      }
    });
  }

  Future<void> arconnectSync() async {
    final isTabFocused = _tabVisibility.isTabFocused();
    logger.i('[ArConnect SYNC] isTabFocused: $isTabFocused');
    if (isTabFocused && await _profileCubit.logoutIfWalletMismatch()) {
      _emitIfOpen(SyncWalletMismatch());
      return;
    }
  }

  void restartArConnectSyncOnFocus() async {
    if (await _profileCubit.isCurrentProfileArConnect()) {
      _restartArConnectOnFocusStreamSubscription =
          _tabVisibility.onTabGetsFocused(() {
        Future.delayed(
          const Duration(seconds: 2),
        ).then(
          (value) => createArConnectSyncStream(),
        );
      });
    }
  }

  var ghostFolders = <FolderID, GhostFolder>{};

  /// Fetches only drive metadata without full content sync.
  /// Used when syncAllDrivesOnLogin is disabled to populate the sidebar.
  /// Emits SyncLoadingDrives for UI feedback but doesn't block waitCurrentSync().
  Future<void> syncMetadataOnly() async {
    logger.d('Starting metadata-only sync');
    final profile = _profileCubit.state;
    if (profile is ProfileLoggedIn) {
      // Emit SyncLoadingDrives for UI feedback (shows "Loading your drives...")
      // This is separate from SyncInProgress so it doesn't block waitCurrentSync()
      _emitIfOpen(SyncLoadingDrives());
      try {
        await _syncRepository.updateUserDrives(
          wallet: profile.user.wallet,
          password: profile.user.password,
          cipherKey: profile.user.cipherKey,
        );
        logger.d('Metadata-only sync completed successfully');
      } catch (e, stackTrace) {
        logger.e('Error fetching drive metadata', e, stackTrace);
        _finishMetadataSync(SyncFailure(error: e, stackTrace: stackTrace));
        return;
      }
      _finishMetadataSync(SyncIdle());
      return;
    } else {
      logger.d('Profile not logged in yet, skipping metadata sync');
      // Still emit SyncIdle so waitCurrentSync() doesn't hang
      _emitIfOpen(SyncIdle());
    }
  }

  /// Ends a metadata-only sync, but only if it is still the thing running.
  ///
  /// This runs under [SyncLoadingDrives], which no "is a sync running" test in
  /// the app recognises - so while it waits on the network the drives page
  /// still offers Sync All Drives, and [startSync]'s own re-entry guard, which
  /// asks only for [SyncInProgress], lets that sync start. Emitting a terminal
  /// state unconditionally then landed it on top of a full sync that was still
  /// walking every drive: the ring went out, every row stopped saying it was
  /// syncing, and everything waiting on [waitCurrentSync] was released against
  /// a half-written database.
  ///
  /// So it only reports if nothing else has taken the state off it.
  void _finishMetadataSync(SyncState state) {
    if (this.state is! SyncLoadingDrives) {
      logger.d('Metadata sync superseded; leaving the state alone');
      return;
    }

    _emitIfOpen(state);
  }

  Future<bool> startSync({
    bool deepSync = false,
    bool skipTabVisibilityCheck = false,
    List<String>? driveIdsToRetry,
    SyncTrigger trigger = SyncTrigger.userInitiated,
  }) async {
    logger.i('Starting Sync');

    if (state is SyncInProgress) {
      logger.d('Sync state is SyncInProgress, aborting sync...');
      return false;
    }

    _syncProgress = SyncProgress.initial();

    /// Whether this sync actually ran to the end, for a logged-in profile.
    ///
    /// The catch below reports the error and falls through to the block that
    /// decides what to emit, and a sync that threw before any drive query ran
    /// - `updateUserDrives()` failing, say - records no `failedQueries`. Left
    /// to itself that block reads "no errors, nothing synced" and announces
    /// "Up to date - nothing new" beside the snackbar saying the sync failed.
    /// A sync with no logged-in profile behind it reaches the same place with
    /// the same nothing to report.
    var ranToCompletion = false;

    /// Whether this sync ended in the catch below. See [_recordSyncRun].
    var threw = false;

    /// What it threw. `_syncProgress.errorMessages` only carries per-drive
    /// failures, so a sync that died before it reached any drive has none -
    /// and the history entry a user opens Troubleshooting to read would carry
    /// no reason at all, which is the one entry the feature exists for.
    Object? thrownError;

    // Create a new cancellation token for this sync
    _currentSyncToken?.dispose(); // Clean up any previous token
    _currentSyncToken = SyncCancellationToken();

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      // Every drive is covered, so no single drive owns this one.
      _syncingDriveId = null;

      _emitIfOpen(SyncInProgress(trigger: trigger));
      // Emit initial progress AFTER SyncInProgress so the indicator is
      // already listening to the stream when we emit
      _publishProgress();

      // Only sync in drives owned by the user if they're logged in.
      logger.d('Checking if user is logged in...');

      if (profile is ProfileLoggedIn) {
        logger.d('User is logged in');

        wallet = profile.user.wallet;
        password = profile.user.password;
        cipherKey = profile.user.cipherKey;

        logger.d('Checking if user is from arconnect...');
        final isArConnect = await _profileCubit.isCurrentProfileArConnect();
        logger.d('User using arconnect: $isArConnect');

        // For ArConnect users, check tab visibility before any operations
        // that require signing. If tab is not focused, skip sync entirely
        // and let the next periodic sync or manual sync handle it.
        // Skip this check for initial sync after login since wallet interaction
        // may momentarily cause the browser to consider the tab unfocused.
        if (isArConnect &&
            !skipTabVisibilityCheck &&
            !_tabVisibility.isTabFocused()) {
          logger.d('Tab hidden for ArConnect user, skipping sync...');
          _emitIfOpen(SyncIdle());
          return false;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logger.d('Uninterruptible activity in progress, skipping sync...');
          _emitIfOpen(SyncIdle());
          return false;
        }

        // Update user drives to discover all drives owned by the user.
        // This must complete before syncAllDrives so drives exist in DB.
        // Emit status message so user sees feedback during this phase
        _syncProgress = _syncProgress.copyWith(
          statusMessage: 'Discovering your drives...',
        );
        _publishProgress();

        await _syncRepository.updateUserDrives(
          wallet: wallet,
          password: password,
          cipherKey: profile.user.cipherKey,
        );

        // Clear status message after discovery completes
        _syncProgress = _syncProgress.copyWith(
          statusMessage: null,
        );
        _publishProgress();
      }

      _promptToSnapshotBloc.add(const SyncRunning(isRunning: true));

      await for (var syncProgress in _syncRepository.syncAllDrives(
          wallet: wallet,
          password: password,
          cipherKey: cipherKey,
          syncDeep: deepSync,
          driveIdsToRetry: driveIdsToRetry,
          cancellationToken: _currentSyncToken,
          txFechedCallback: (driveId, txCount) {
            _promptToSnapshotBloc.add(
              CountSyncedTxs(
                driveId: driveId,
                txsSyncedWithGqlCount: txCount,
                wasDeepSync: deepSync,
              ),
            );
          })) {
        _syncProgress = syncProgress;
        _publishProgress();
      }

      ranToCompletion = profile is ProfileLoggedIn;

      // Only refresh balance if drives were actually synced (skip after no-op)
      if (profile is ProfileLoggedIn && _syncProgress.drivesSynced > 0) {
        _profileCubit.refreshBalance();
      }

      logger.i('Transaction statuses updated');
    } catch (err, stackTrace) {
      if (err is SyncCancelledException) {
        logger.i('Sync cancelled by user');
        // Clean up the cancellation token
        _currentSyncToken?.dispose();
        _currentSyncToken = null;

        _emitIfOpen(SyncCancelled(
          drivesCompleted: _syncProgress.drivesSynced,
          totalDrives: _syncProgress.drivesCount,
          cancelledAt: DateTime.now(),
          trigger: trigger,
        ));
        unawaited(_recordSyncRun(SyncRunOutcome.cancelled, trigger));
        _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));
        return false; // Exit early for cancellation - nothing may be reported
      }
      logger.e('Error syncing drives', err, stackTrace);
      // Noted, not handled: `addError` below is still the whole of what
      // happens to this error. The flag only decides which outcome the history
      // entry carries, so a sync that threw is written down as a sync that
      // failed rather than falling through as one that quietly did nothing.
      threw = true;
      thrownError = err;
      addError(err);
    } finally {
      // Clean up the cancellation token (for non-cancellation cases)
      if (_currentSyncToken != null) {
        _currentSyncToken?.dispose();
        _currentSyncToken = null;
      }
    }
    _lastSync = DateTime.now();

    logger.i(
      'Syncing drives finished. Drives quantity: ${_syncProgress.drivesCount}.'
      ' The total progress was'
      ' ${(_syncProgress.progress * 100).roundToDouble()}%.'
      ' The sync process took:'
      ' ${_lastSync!.difference(_initSync).inMilliseconds}ms to finish',
    );

    _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));

    unawaited(_updateContext());

    _captureSkippedEntities(_syncProgress);

    unawaited(_recordDrivesSynced());

    // Check if sync completed with errors (only for non-cancelled syncs)
    if (_syncProgress.hasErrors) {
      logger.w('Sync completed with ${_syncProgress.failedQueries} errors');
      _emitIfOpen(SyncCompleteWithErrors(
        failedDrives: _syncProgress.failedQueries,
        totalDrives: _syncProgress.drivesCount,
        failedDriveIds: _syncProgress.failedDriveIds,
        errorMessages: _syncProgress.errorMessages,
        skippedEntityCount: _syncProgress.skippedEntityCount,
        skippedEntityTxIdsByDrive: _syncProgress.skippedEntityTxIdsByDrive,
        trigger: trigger,
      ));
      unawaited(_recordSyncRun(SyncRunOutcome.completedWithErrors, trigger));
    } else if (ranToCompletion) {
      _emitIfOpen(_syncComplete(trigger));
      unawaited(_recordSyncRun(SyncRunOutcome.completed, trigger));
    } else {
      // Nothing to report, so nothing is claimed - exactly what this path
      // emitted before results existed.
      _emitIfOpen(SyncIdle());
      if (threw) {
        unawaited(_recordSyncRun(
          SyncRunOutcome.failed,
          trigger,
          error: thrownError,
        ));
      }
    }

    return true;
  }

  /// Syncs a single drive by its ID with optional deep sync.
  /// Similar to startSync but only syncs the specified drive.
  ///
  /// Returns whether a sync actually ran for this drive. False means nothing
  /// was fetched and nothing was written - the request was refused because a
  /// sync was already running, or the tab was hidden, or an uninterruptible
  /// activity was in the way. It is returned rather than left to the caller to
  /// infer from the state, because a caller that infers gets it wrong the same
  /// way every time: it reads the drive afterwards, finds it as empty as it
  /// was, and reports that the sync looked and found nothing - see
  /// `DriveDetailCubit.syncCurrentDrive`.
  Future<bool> startSyncForDrive({
    required String driveId,
    bool deepSync = false,
    SyncTrigger trigger = SyncTrigger.userInitiated,
  }) async {
    logger.i('Starting Sync for drive: $driveId, deepSync: $deepSync');

    // One sync at a time, and no queue behind it. This used to await the
    // running sync and then re-check, so a second request either waited
    // invisibly for minutes or was silently discarded depending on what else
    // had started meanwhile - and from the outside those are indistinguishable.
    //
    // The refusal is here rather than at the call sites because this is the
    // one door all of them go through. It is not the whole answer, though: a
    // refusal nobody can see is the same silence in a different place, so
    // every affordance that reaches this is drawn as unavailable while a sync
    // runs - see `_SyncButtonMenu`, `DriveActionsMenu` and the drive detail
    // menus.
    if (state is SyncInProgress) {
      logger.d('A sync is already running; refusing single drive sync');
      return false;
    }

    // Mark as single drive sync from the start so the UI shows the right title
    _syncProgress = SyncProgress.initial().copyWith(
      isSingleDriveSync: true,
      drivesCount: 1,
    );

    /// See [startSync]: the single-drive path falls through to the same
    /// decision after the same catch, and must make the same non-claim.
    var ranToCompletion = false;

    /// Whether this sync ended in the catch below. See [_recordSyncRun].
    var threw = false;

    /// What it threw. `_syncProgress.errorMessages` only carries per-drive
    /// failures, so a sync that died before it reached any drive has none -
    /// and the history entry a user opens Troubleshooting to read would carry
    /// no reason at all, which is the one entry the feature exists for.
    Object? thrownError;

    // Create a new cancellation token for this sync
    _currentSyncToken?.dispose();
    _currentSyncToken = SyncCancellationToken();

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      // Which drive this sync is for, so a surface listing drives can say
      // "Syncing..." on that row alone.
      _syncingDriveId = driveId;

      _emitIfOpen(SyncInProgress(trigger: trigger));
      // Emit initial progress AFTER SyncInProgress so the indicator is
      // already listening to the stream when we emit
      _publishProgress();

      if (profile is ProfileLoggedIn) {
        wallet = profile.user.wallet;
        password = profile.user.password;
        cipherKey = profile.user.cipherKey;

        final isArConnect = await _profileCubit.isCurrentProfileArConnect();

        // For ArConnect users, check tab visibility
        if (isArConnect && !_tabVisibility.isTabFocused()) {
          logger.d(
              'Tab hidden for ArConnect user, skipping single drive sync...');
          _emitIfOpen(SyncIdle());
          // Skipped, not run: nothing was fetched, so there is no result for
          // anyone to report.
          return false;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logger.d(
              'Uninterruptible activity in progress, skipping single drive sync...');
          _emitIfOpen(SyncIdle());
          return false;
        }

        // Load drive keys so private drives can be decrypted
        await _syncRepository.updateUserDrives(
          wallet: wallet,
          password: password,
          cipherKey: cipherKey,
        );
      }

      _promptToSnapshotBloc.add(const SyncRunning(isRunning: true));

      await for (var syncProgress in _syncRepository.syncSingleDrive(
        driveId: driveId,
        wallet: wallet,
        password: password,
        cipherKey: cipherKey,
        syncDeep: deepSync,
        cancellationToken: _currentSyncToken,
        txFechedCallback: (driveId, txCount) {
          _promptToSnapshotBloc.add(
            CountSyncedTxs(
              driveId: driveId,
              txsSyncedWithGqlCount: txCount,
              wasDeepSync: deepSync,
            ),
          );
        },
      )) {
        _syncProgress = syncProgress;
        _publishProgress();
      }

      ranToCompletion = profile is ProfileLoggedIn;

      // Only refresh balance if drives were actually synced
      if (profile is ProfileLoggedIn && _syncProgress.drivesSynced > 0) {
        _profileCubit.refreshBalance();
      }

      logger.i('Single drive sync completed');
    } catch (err, stackTrace) {
      if (err is SyncCancelledException) {
        logger.i('Single drive sync cancelled by user');
        _currentSyncToken?.dispose();
        _currentSyncToken = null;

        _emitIfOpen(SyncCancelled(
          drivesCompleted: _syncProgress.drivesSynced,
          totalDrives: _syncProgress.drivesCount,
          cancelledAt: DateTime.now(),
          trigger: trigger,
        ));
        _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));
        // False, exactly as [startSync] answers the same question. The two
        // used to disagree, and a caller that believed this one emitted a
        // loading state, took `true` for "a sync ran", and then found the
        // state was `SyncCancelled` and returned without emitting anything -
        // leaving the explorer on "Opening Drive X" with a sweeping bar that
        // nothing ever cleared. A cancelled sync started nothing the caller
        // may report, whichever door it came through.
        unawaited(_recordSyncRun(SyncRunOutcome.cancelled, trigger));
        return false;
      }
      logger.e('Error syncing single drive', err, stackTrace);
      // Noted, not handled - see the same line in [startSync].
      threw = true;
      thrownError = err;
      addError(err);
    } finally {
      if (_currentSyncToken != null) {
        _currentSyncToken?.dispose();
        _currentSyncToken = null;
      }

      // Released on every path out, cancellation included: nothing is running
      // for this drive any more.
      _syncingDriveId = null;
    }

    _lastSync = DateTime.now();

    logger.i(
      'Single drive sync finished. Sync took: ${_lastSync!.difference(_initSync).inMilliseconds}ms',
    );

    _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));

    _captureSkippedEntities(_syncProgress);

    unawaited(_recordDrivesSynced());

    // Check if sync completed with errors
    if (_syncProgress.hasErrors) {
      logger.w('Single drive sync completed with errors');
      _emitIfOpen(SyncCompleteWithErrors(
        failedDrives: _syncProgress.failedQueries,
        totalDrives: _syncProgress.drivesCount,
        failedDriveIds: _syncProgress.failedDriveIds,
        errorMessages: _syncProgress.errorMessages,
        skippedEntityCount: _syncProgress.skippedEntityCount,
        skippedEntityTxIdsByDrive: _syncProgress.skippedEntityTxIdsByDrive,
        trigger: trigger,
      ));
      unawaited(_recordSyncRun(SyncRunOutcome.completedWithErrors, trigger));
    } else if (ranToCompletion) {
      _emitIfOpen(_syncComplete(trigger));
      unawaited(_recordSyncRun(SyncRunOutcome.completed, trigger));
    } else {
      _emitIfOpen(SyncIdle());
      if (threw) {
        unawaited(_recordSyncRun(
          SyncRunOutcome.failed,
          trigger,
          error: thrownError,
        ));
      }
    }

    return true;
  }

  /// Writes down that the drives this sync walked are current as of now.
  ///
  /// Per drive rather than one global timestamp, because "when did we last
  /// look at this drive" is the only question the drives list can answer
  /// honestly: a single-drive sync leaves every other drive exactly as stale
  /// as it was.
  ///
  /// Fire and forget, and never allowed to take a finished sync down with it.
  /// The sync has already succeeded by the time this runs; a preferences write
  /// that fails is worth a log line and nothing more.
  Future<void> _recordDrivesSynced() async {
    final syncedDriveIds = _syncProgress.syncedDriveIds;

    if (syncedDriveIds.isEmpty) {
      return;
    }

    // See [_recordSyncRun]: this lands after logout has cleared the store.
    if (isClosed) {
      return;
    }

    try {
      await _userPreferencesRepository.saveDrivesLastSynced(syncedDriveIds);
    } catch (e, stackTrace) {
      logger.e(
        'Could not record when these drives were last synced',
        e,
        stackTrace,
      );
    }
  }

  /// Writes down what this sync did, for the user to read later.
  ///
  /// Everything here is read off the progress the sync already reported and
  /// the start time it was already counting from: nothing is recounted, no
  /// drive is queried, and no network request is made. It is the same
  /// fire-and-forget contract as [_recordDrivesSynced] - a sync that has
  /// already finished must not be taken down by a preferences write that
  /// failed.
  ///
  /// A sync that was refused before it started - a hidden tab, an
  /// uninterruptible upload, a second request while one was already running -
  /// is deliberately not recorded. Nothing was fetched, so there is nothing to
  /// say about it, and a history full of runs that never happened is a history
  /// nobody can read. `syncMetadataOnly` is not recorded either: it refreshes
  /// the drive list and syncs no drive, and it reports its own failure on the
  /// indicator.
  Future<void> _recordSyncRun(
    SyncRunOutcome outcome,
    SyncTrigger trigger, {
    Object? error,
  }) async {
    // Every caller fires this `unawaited`, and a sync cancelled by [close] only
    // notices its token at the repository's next checkpoint - a network round
    // trip away. Logging out clears this store (`UserPreferencesRepository`
    // .clear, off `onAuthStateChanged(null)`), so without this guard the write
    // reliably lands afterwards: it reads the emptied history and puts one
    // entry back, carrying the previous wallet's drive name, error messages
    // and timings. The next wallet to log in then reads a sync it never ran.
    if (isClosed) {
      return;
    }

    try {
      await _userPreferencesRepository.recordSyncRun(
        SyncRun(
          startedAt: _initSync,
          took: DateTime.now().difference(_initSync),
          trigger: trigger,
          // Named only when this sync was for one drive. The all-drives case
          // has no drive to name, and the trigger already says what it was.
          driveName:
              _syncProgress.isSingleDriveSync ? _syncProgress.driveName : null,
          outcome: outcome,
          itemsFound: _syncProgress.entitiesSynced,
          skippedEntityCount: _syncProgress.skippedEntityCount,
          failedDrives: _syncProgress.failedQueries,
          totalDrives: _syncProgress.drivesCount,
          // A sync that threw before reaching a drive has no per-drive
          // messages, so its own error is what there is to report.
          errorMessages: _syncProgress.errorMessages.isNotEmpty
              ? _syncProgress.errorMessages
              : error != null
                  ? {'': error.toString()}
                  : const <String, String>{},
        ),
      );
    } catch (e, stackTrace) {
      logger.e('Could not record what this sync did', e, stackTrace);
    }
  }

  Future<void> _updateContext() async {
    try {
      var context = logger.context;

      final numberOfFiles = await _syncRepository.numberOfFilesInWallet();
      final numberOfFolders = await _syncRepository.numberOfFoldersInWallet();

      logger.setContext(
        context.copyWith(
          numberOfDrives: _syncProgress.drivesCount,
          numberOfFiles: numberOfFiles,
          numberOfFolders: numberOfFolders,
        ),
      );
    } catch (e) {
      logger.w('Error setting context after sync');
    }
  }

  int calculateSyncLastBlockHeight(int lastBlockHeight) {
    if (_lastSync != null) {
      return lastBlockHeight;
    } else {
      return max(lastBlockHeight - kBlockHeightLookBack, 0);
    }
  }

  /// Cancel the current sync operation
  void cancelSync() {
    if (state is SyncInProgress && _currentSyncToken != null) {
      logger.i('Requesting sync cancellation');
      _currentSyncToken!.cancel();
    }
  }

  /// Clear the cancelled state and return to idle
  void clearCancelledState() {
    if (state is SyncCancelled) {
      emit(SyncIdle());
    }
  }

  /// Clear the error state and return to idle
  void clearErrorState() {
    if (state is SyncCompleteWithErrors) {
      emit(SyncIdle());
    }
  }

  /// Retry syncing only the drives that failed in the previous sync.
  Future<void> retryFailedDrives(List<String> driveIds) async {
    if (driveIds.isEmpty) return;

    logger.i('Retrying ${driveIds.length} failed drives');
    await startSync(driveIdsToRetry: driveIds);
  }

  /// Get the current sync progress
  SyncProgress get syncProgress => _syncProgress;

  @override
  void onError(Object error, StackTrace stackTrace) {
    logger.e('An error occured on SyncCubit', error, stackTrace);

    if (isClosed) {
      logger.d('SyncCubit is closed, aborting onError...');
      return;
    }

    // And it stays there. It used to fall straight back to `SyncIdle` in the
    // same turn, which made `driveListRefreshFailed` - defined as `state is
    // SyncFailure` - false by the time anything read it. A drive list that
    // could not be fetched then looked exactly like a wallet with no drives,
    // and the app offered "Getting Started" and two create-a-drive buttons to
    // someone whose drives simply had not loaded.
    //
    // Every waiter uses [syncHasFinished], which counts this as over.
    emit(SyncFailure(error: error, stackTrace: stackTrace));

    super.onError(error, stackTrace);
  }

  /// Shuts the cubit down, and the sync with it.
  ///
  /// The running sync is cancelled here, not merely abandoned. This cubit is
  /// created per session and closed on logout, and `ArDriveAuth.logout()`
  /// empties every table *before* the close reaches here - so a sync left
  /// running spends the following minutes writing the previous wallet's drives
  /// and revisions back into the database the logout just cleared, where
  /// `DrivesCubit` watches an unfiltered `allDrives()` and shows them to
  /// whoever logs in next.
  ///
  /// It was unreachable until this stack: a running sync used to hold a
  /// full-screen scrim over the app, Log Out included. The scrim is gone by
  /// design - a sync reports on the top bar's indicator without taking the
  /// app - so every control is live mid-sync and this is now an ordinary thing
  /// to do.
  ///
  /// The sync does not stop the instant this returns: the repository notices
  /// the cancellation at its next checkpoint. That is why the emits and the
  /// progress publishes are guarded rather than trusted - see [_emitIfOpen]
  /// and [_publishProgress] - and why the repository clears its own per-sync
  /// state at the *start* of every sync rather than at the end, so a straggler
  /// cannot leave its counts behind for the next session's sync to report.
  @override
  Future<void> close() async {
    logger.i('Closing SyncCubit instance');

    // First, so the sync begins unwinding while the subscriptions below are
    // being torn down rather than after.
    _currentSyncToken?.cancel();
    _currentSyncToken?.dispose();
    _currentSyncToken = null;

    await _syncSub?.cancel();
    await _arconnectSyncSub?.cancel();
    await _restartOnFocusStreamSubscription?.cancel();
    await _restartArConnectOnFocusStreamSubscription?.cancel();

    _syncSub = null;
    _arconnectSyncSub = null;
    _restartOnFocusStreamSubscription = null;
    _restartArConnectOnFocusStreamSubscription = null;

    // Closed with the cubit that owns it. It is a broadcast controller with no
    // listeners left once the top bar is gone, and leaving it open leaks it
    // along with everything a straggling sync adds to it.
    await syncProgressController.close();

    await super.close();

    logger.i('SyncCubit closed');
  }
}
