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

/// Who asked for a sync.
///
/// A [userInitiated] sync is one the user pressed a button for, so it is
/// allowed to hold the whole app while it runs. A [background] sync is one that
/// merely happened - the sync on login is the only one in production - and has
/// to stay out of the way: the app remains usable and the top bar's indicator
/// is the only place it reports itself.
enum SyncTrigger {
  background,
  userInitiated,
}

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
  static bool _syncHasFinished(SyncState state) =>
      state is SyncIdle ||
      state is SyncFailure ||
      state is SyncCancelled ||
      state is SyncCompleteWithErrors ||
      state is SyncLoadingDrives;

  Future<void> waitCurrentSync() async {
    if (_syncHasFinished(state)) return;

    await for (final state in stream) {
      if (_syncHasFinished(state)) break;
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
        // Say so. This used to be swallowed because a full sync ran alongside
        // it and reported its own failure; now it is the only thing that runs
        // on a default login, so a gateway that will not answer would leave an
        // empty sidebar, no error, and nothing to explain it.
        emit(SyncFailure(error: e, stackTrace: stackTrace));
        return;
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
    SyncTrigger trigger = SyncTrigger.userInitiated,
  }) async {
    logger.i('Starting Sync');

    if (state is SyncInProgress) {
      logger.d('Sync state is SyncInProgress, aborting sync...');
      return;
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

    // Create a new cancellation token for this sync
    _currentSyncToken?.dispose(); // Clean up any previous token
    _currentSyncToken = SyncCancellationToken();

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      emit(SyncInProgress(trigger: trigger));
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

        emit(SyncCancelled(
          drivesCompleted: _syncProgress.drivesSynced,
          totalDrives: _syncProgress.drivesCount,
          cancelledAt: DateTime.now(),
          trigger: trigger,
        ));
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

    _captureSkippedEntities(_syncProgress);

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
        trigger: trigger,
      ));
    } else if (ranToCompletion) {
      emit(_syncComplete(trigger));
    } else {
      // Nothing to report, so nothing is claimed - exactly what this path
      // emitted before results existed.
      emit(SyncIdle());
    }
  }

  /// Syncs a single drive by its ID with optional deep sync.
  /// Similar to startSync but only syncs the specified drive.
  Future<void> startSyncForDrive({
    required String driveId,
    bool deepSync = false,
    SyncTrigger trigger = SyncTrigger.userInitiated,
  }) async {
    logger.i('Starting Sync for drive: $driveId, deepSync: $deepSync');

    if (state is SyncInProgress) {
      logger.d('Waiting for current sync to finish before single drive sync');
      await waitCurrentSync();
      // Re-check: another caller may have started syncing while we waited
      if (state is SyncInProgress) {
        logger.d(
            'Another sync started while waiting, aborting single drive sync');
        return;
      }
    }

    // Mark as single drive sync from the start so the UI shows the right title
    _syncProgress = SyncProgress.initial().copyWith(
      isSingleDriveSync: true,
      drivesCount: 1,
    );

    /// See [startSync]: the single-drive path falls through to the same
    /// decision after the same catch, and must make the same non-claim.
    var ranToCompletion = false;

    // Create a new cancellation token for this sync
    _currentSyncToken?.dispose();
    _currentSyncToken = SyncCancellationToken();

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      emit(SyncInProgress(trigger: trigger));
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
          logger.d(
              'Tab hidden for ArConnect user, skipping single drive sync...');
          emit(SyncIdle());
          return;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logger.d(
              'Uninterruptible activity in progress, skipping single drive sync...');
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

        emit(SyncCancelled(
          drivesCompleted: _syncProgress.drivesSynced,
          totalDrives: _syncProgress.drivesCount,
          cancelledAt: DateTime.now(),
          trigger: trigger,
        ));
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

    _captureSkippedEntities(_syncProgress);

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
        trigger: trigger,
      ));
    } else if (ranToCompletion) {
      emit(_syncComplete(trigger));
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
