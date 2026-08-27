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
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

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

  /// Exposed for the sync modal to display elapsed time.
  DateTime get syncStartTime => _initSync;

  SyncProgress _syncProgress = SyncProgress.initial();
  SyncCancellationToken? _currentSyncToken;

  /// What the last sync to **examine** each drive reported for it: the
  /// transaction ids it could not read, empty when it read everything.
  ///
  /// Keyed by drive, and updated per drive rather than replaced per sync,
  /// because a sync only reports about the drives it opened. The activity
  /// probe sets aside drives it believes unchanged, and a scoped sync visits
  /// one drive; in both cases the report is silent about the rest, and that
  /// silence is not evidence. A drive with no entry here has not been examined
  /// in this session and nothing is known about it.
  ///
  /// Carrying an entry forward across syncs that did not examine its drive is
  /// the honest reading, not a convenience: nothing synced that drive, so
  /// neither its rows nor its `lastBlockHeight` moved, and the last report
  /// about it is still true of it. What must *not* be carried forward is a
  /// report from a sync that examined the drive and then stopped before
  /// reporting - see [_recordExaminedDrives].
  final Map<String, List<String>> _skipsByExaminedDrive = {};

  /// Transaction ids of entities sync could not read, keyed by drive id, for
  /// the drives that have any. Retained on the cubit — not just on the
  /// terminal state — so it survives a plain [SyncIdle] completion, which is
  /// the common case when items are skipped but no drive outright fails.
  ///
  /// This is currently the only record that anything was dropped. A later pass
  /// renders it as "failed files"; persisting and retrying these across syncs
  /// is described in `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
  Map<String, List<String>> get lastSyncSkippedEntityTxIdsByDrive => {
        for (final entry in _skipsByExaminedDrive.entries)
          if (entry.value.isNotEmpty) entry.key: entry.value,
      };

  int get lastSyncSkippedEntityCount =>
      _skipsByExaminedDrive.values.fold(0, (sum, txIds) => sum + txIds.length);

  DateTime? _lastSyncCompletedAt;

  /// When a sync last ran to completion, or `null` if none has in this
  /// session.
  ///
  /// The distinction matters to anything reading
  /// [lastSyncSkippedEntityTxIdsByDrive] as evidence: the map starts empty, so
  /// "no sync has run" and "a sync ran and skipped nothing" are otherwise the
  /// same value. A sync that did not run to the end of its progress stream -
  /// cancelled, or failed - leaves this at whatever the previous completed
  /// sync set.
  DateTime? get lastSyncCompletedAt => _lastSyncCompletedAt;

  /// The drives some completed sync examined and reported on, which is what a
  /// reader may treat its silence about skips as evidence for.
  ///
  /// Never a claim about drives no sync opened. A sync reports skips only for
  /// what it read, so the probe-skipped drives of a routine sweep, and every
  /// drive but one of a scoped sync, are absent here rather than clean.
  Set<String>? get lastSyncCoveredDriveIds =>
      _skipsByExaminedDrive.keys.toSet();

  /// Folds a sync's report into the per-drive ledger.
  ///
  /// [reachedTheEnd] is the whole guard, and it is not defensive. Both entry
  /// points call this after their `try`/`catch`, which is the right place for
  /// the state emission that follows it and the wrong place for this: a sync
  /// whose progress stream ended in an error arrives here too, having produced
  /// no final report, and stamping [lastSyncCompletedAt] then would say a sync
  /// finished and found nothing to skip when in truth it stopped early and
  /// never looked. Both also call it from their cancellation branch, which
  /// returns before reaching that point.
  ///
  /// What reads that stamp is `driveStateSyncSkipStatus`, the precondition on
  /// publishing a drive state artifact. An artifact records the gap it was
  /// built over permanently and immutably on Arweave, so this being wrong is
  /// not a stale reading - it is a permanent one.
  ///
  /// Three rules, and the middle one is the fix this method exists for:
  ///
  ///  * a sync that stopped early **erases** what it knew about the drives it
  ///    had opened. It may have advanced their `lastBlockHeight` past entities
  ///    it never read - the watermark is written per drive, inside the drive's
  ///    own work - and then died without saying so. An older report about
  ///    those drives is no longer true of them;
  ///  * a sync that reached its end records an answer **only for the drives it
  ///    examined**. Drives the probe set aside as unchanged are not in that
  ///    set, are not in `failedDriveIds` either, and so used to satisfy every
  ///    check and read as clean off the back of a sync that never opened them.
  ///    They now keep whatever was last established about them, which is
  ///    nothing at all unless some sync did open them;
  ///  * a drive that was examined and **failed** loses its entry. Its sync
  ///    threw part-way, from anywhere in the drive's work including after its
  ///    watermark was written, so it is in the same position as the first rule
  ///    and an older report about it is equally stale.
  ///
  /// A report naming skips for a drive it did not list as examined is a
  /// contradiction. It is folded in anyway: the direction that refuses to
  /// publish is the one to take when the inputs disagree.
  void _recordExaminedDrives(
    SyncProgress progress, {
    required bool reachedTheEnd,
  }) {
    final examined = {
      ...progress.examinedDriveIds,
      ...progress.skippedEntityTxIdsByDrive.keys,
    };

    if (!reachedTheEnd) {
      _skipsByExaminedDrive.removeWhere((id, _) => examined.contains(id));
      return;
    }

    _lastSyncCompletedAt = DateTime.now();

    final failed = progress.failedDriveIds.toSet();
    for (final driveId in examined) {
      if (failed.contains(driveId)) {
        _skipsByExaminedDrive.remove(driveId);
        continue;
      }
      _skipsByExaminedDrive[driveId] = List.unmodifiable(
        progress.skippedEntityTxIdsByDrive[driveId] ?? const <String>[],
      );
    }
  }

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
  Future<void> waitCurrentSync() async {
    if (state is! SyncIdle && state is! SyncLoadingDrives) {
      await for (var state in stream) {
        if (state is SyncIdle ||
            state is SyncFailure ||
            state is SyncCancelled ||
            state is SyncCompleteWithErrors ||
            state is SyncLoadingDrives) {
          break;
        }
      }
    }
  }

  void createSyncStream() async {
    logger.d('Creating sync stream to periodically call sync automatically');

    // Note: Initial state is already SyncLoadingDrives (set in constructor)
    // to prevent race conditions with waitCurrentSync()

    // Check if syncAllDrivesOnLogin preference is enabled before initial sync
    final preferences = await _userPreferencesRepository.load();
    if (preferences.syncAllDrivesOnLogin) {
      // Start initial sync immediately without waiting for async operations.
      // Skip tab visibility check for initial sync because the user just logged in
      // (which requires wallet interaction, proving they're active). The wallet popup
      // may cause the browser to consider the tab unfocused momentarily.
      startSync(skipTabVisibilityCheck: true);
    } else {
      logger.d('Skipping full sync: syncAllDrivesOnLogin is disabled');
      syncMetadataOnly();
    }

    // Cancel any existing subscription before creating a new one
    await _syncSub?.cancel();

    _syncSub = Stream.periodic(
            Duration(seconds: _configService.config.autoSyncIntervalInSeconds))
        // Do not start another sync until the previous sync has completed.
        .map((value) {
      /// Only start sync if autoSync is enabled.
      if (_configService.config.autoSync) {
        return Stream.fromFuture(startSync());
      }
    }).listen((_) {
      logger.d('Listening to startSync periodic stream');
    });
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
      emit(SyncWalletMismatch());
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
      emit(SyncLoadingDrives());
      try {
        await _syncRepository.updateUserDrives(
          wallet: profile.user.wallet,
          password: profile.user.password,
          cipherKey: profile.user.cipherKey,
        );
        logger.d('Metadata-only sync completed successfully');
      } catch (e, stackTrace) {
        logger.e('Error fetching drive metadata', e, stackTrace);
      }
      emit(SyncIdle());
    } else {
      logger.d('Profile not logged in yet, skipping metadata sync');
      // Still emit SyncIdle so waitCurrentSync() doesn't hang
      emit(SyncIdle());
    }
  }


  Future<void> startSync({
    bool deepSync = false,
    bool skipTabVisibilityCheck = false,
    List<String>? driveIdsToRetry,
  }) async {
    logger.i('Starting Sync');

    if (state is SyncInProgress) {
      logger.d('Sync state is SyncInProgress, aborting sync...');
      return;
    }

    _syncProgress = SyncProgress.initial();

    // Create a new cancellation token for this sync
    _currentSyncToken?.dispose(); // Clean up any previous token
    _currentSyncToken = SyncCancellationToken();

    /// Set only where the progress stream ran to its natural end. Everything
    /// after the `catch` below runs for a failed sync as well as a successful
    /// one, so this is what tells the two apart. See [_recordExaminedDrives].
    var reachedTheEnd = false;

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      emit(SyncInProgress());
      // Emit initial progress AFTER SyncInProgress so the modal is already
      // listening to the stream when we emit
      syncProgressController.add(_syncProgress);

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
          emit(SyncIdle());
          return;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logger.d('Uninterruptible activity in progress, skipping sync...');
          emit(SyncIdle());
          return;
        }

        // Update user drives to discover all drives owned by the user.
        // This must complete before syncAllDrives so drives exist in DB.
        // Emit status message so user sees feedback during this phase
        _syncProgress = _syncProgress.copyWith(
          statusMessage: 'Discovering your drives...',
        );
        syncProgressController.add(_syncProgress);

        await _syncRepository.updateUserDrives(
          wallet: wallet,
          password: password,
          cipherKey: profile.user.cipherKey,
        );

        // Clear status message after discovery completes
        _syncProgress = _syncProgress.copyWith(
          statusMessage: null,
        );
        syncProgressController.add(_syncProgress);
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
        syncProgressController.add(_syncProgress);
      }

      // The stream closed without an error, so the sync's final report - the
      // progress carrying `skippedEntityTxIdsByDrive` - has been seen.
      reachedTheEnd = true;

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

        emit(SyncCancelled(
          drivesCompleted: _syncProgress.drivesSynced,
          totalDrives: _syncProgress.drivesCount,
          cancelledAt: DateTime.now(),
        ));
        // This branch returns before the record below, so it makes its own.
        // A cancelled sync had opened drives and may have advanced their
        // watermarks past entities it never read - it is a sync that stopped
        // early, and the drives it touched must lose their verdict like any
        // other. Cancellation is a *user's* choice, but the state it leaves
        // behind is not.
        _recordExaminedDrives(_syncProgress, reachedTheEnd: false);
        _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));
        return; // Exit early for cancellation
      }
      logger.e('Error syncing drives', err, stackTrace);
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

    // Which drives this sweep examined comes from the sweep itself, not from
    // what it was asked to do: `driveIdsToRetry` is the request, and even a
    // request for every drive is answered by the activity probe with a
    // subset.
    _recordExaminedDrives(_syncProgress, reachedTheEnd: reachedTheEnd);

    // Check if sync completed with errors (only for non-cancelled syncs)
    if (_syncProgress.hasErrors) {
      logger.w('Sync completed with ${_syncProgress.failedQueries} errors');
      emit(SyncCompleteWithErrors(
        failedDrives: _syncProgress.failedQueries,
        totalDrives: _syncProgress.drivesCount,
        failedDriveIds: _syncProgress.failedDriveIds,
        errorMessages: _syncProgress.errorMessages,
        skippedEntityCount: _syncProgress.skippedEntityCount,
        skippedEntityTxIdsByDrive: _syncProgress.skippedEntityTxIdsByDrive,
      ));
    } else {
      emit(SyncIdle());
    }
  }

  /// Syncs a single drive by its ID with optional deep sync.
  /// Similar to startSync but only syncs the specified drive.
  Future<void> startSyncForDrive({
    required String driveId,
    bool deepSync = false,
  }) async {
    logger.i('Starting Sync for drive: $driveId, deepSync: $deepSync');

    if (state is SyncInProgress) {
      logger.d('Waiting for current sync to finish before single drive sync');
      await waitCurrentSync();
      // Re-check: another caller may have started syncing while we waited
      if (state is SyncInProgress) {
        logger.d('Another sync started while waiting, aborting single drive sync');
        return;
      }
    }

    // Mark as single drive sync from the start so the UI shows the right title
    _syncProgress = SyncProgress.initial().copyWith(
      isSingleDriveSync: true,
      drivesCount: 1,
    );

    // Create a new cancellation token for this sync
    _currentSyncToken?.dispose();
    _currentSyncToken = SyncCancellationToken();

    /// See [_recordExaminedDrives] - the same reason as in [startSync].
    var reachedTheEnd = false;

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      emit(SyncInProgress());
      // Emit initial progress AFTER SyncInProgress so the modal is already
      // listening to the stream when we emit
      syncProgressController.add(_syncProgress);

      if (profile is ProfileLoggedIn) {
        wallet = profile.user.wallet;
        password = profile.user.password;
        cipherKey = profile.user.cipherKey;

        final isArConnect = await _profileCubit.isCurrentProfileArConnect();

        // For ArConnect users, check tab visibility
        if (isArConnect && !_tabVisibility.isTabFocused()) {
          logger.d('Tab hidden for ArConnect user, skipping single drive sync...');
          emit(SyncIdle());
          return;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logger.d('Uninterruptible activity in progress, skipping single drive sync...');
          emit(SyncIdle());
          return;
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
        syncProgressController.add(_syncProgress);
      }

      // The stream closed without an error, so the sync's final report has
      // been seen.
      reachedTheEnd = true;

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

        emit(SyncCancelled(
          drivesCompleted: _syncProgress.drivesSynced,
          totalDrives: _syncProgress.drivesCount,
          cancelledAt: DateTime.now(),
        ));
        // See the same branch in [startSync] - this one returns early too.
        _recordExaminedDrives(_syncProgress, reachedTheEnd: false);
        _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));
        return;
      }
      logger.e('Error syncing single drive', err, stackTrace);
      addError(err);
    } finally {
      if (_currentSyncToken != null) {
        _currentSyncToken?.dispose();
        _currentSyncToken = null;
      }
    }

    _lastSync = DateTime.now();

    logger.i(
      'Single drive sync finished. Sync took: ${_lastSync!.difference(_initSync).inMilliseconds}ms',
    );

    _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));

    // Not `{driveId}`: a drive that is not in the database is never opened,
    // and the repository's report says so.
    _recordExaminedDrives(_syncProgress, reachedTheEnd: reachedTheEnd);

    // Check if sync completed with errors
    if (_syncProgress.hasErrors) {
      logger.w('Single drive sync completed with errors');
      emit(SyncCompleteWithErrors(
        failedDrives: _syncProgress.failedQueries,
        totalDrives: _syncProgress.drivesCount,
        failedDriveIds: _syncProgress.failedDriveIds,
        errorMessages: _syncProgress.errorMessages,
        skippedEntityCount: _syncProgress.skippedEntityCount,
        skippedEntityTxIdsByDrive: _syncProgress.skippedEntityTxIdsByDrive,
      ));
    } else {
      emit(SyncIdle());
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
    return startSync(driveIdsToRetry: driveIds);
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

    emit(SyncFailure(error: error, stackTrace: stackTrace));

    emit(SyncIdle());
    super.onError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    logger.i('Closing SyncCubit instance');
    await _syncSub?.cancel();
    await _arconnectSyncSub?.cancel();
    await _restartOnFocusStreamSubscription?.cancel();
    await _restartArConnectOnFocusStreamSubscription?.cancel();

    _syncSub = null;
    _arconnectSyncSub = null;
    _restartOnFocusStreamSubscription = null;
    _restartArConnectOnFocusStreamSubscription = null;

    await super.close();

    logger.i('SyncCubit closed');
  }
}
