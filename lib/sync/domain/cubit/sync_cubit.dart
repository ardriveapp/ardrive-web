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
import 'package:ardrive/sync/domain/sync_progress.dart';
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

  StreamSubscription? _restartOnFocusStreamSubscription;
  StreamSubscription? _restartArConnectOnFocusStreamSubscription;
  StreamSubscription? _syncSub;
  StreamSubscription? _arconnectSyncSub;
  final StreamController<SyncProgress> syncProgressController =
      StreamController<SyncProgress>.broadcast();
  DateTime? _lastSync;
  late DateTime _initSync;
  late SyncProgress _syncProgress;

  SyncCubit({
    required ProfileCubit profileCubit,
    required ActivityCubit activityCubit,
    required PromptToSnapshotBloc promptToSnapshotBloc,
    required TabVisibilitySingleton tabVisibility,
    required ConfigService configService,
    required ActivityTracker activityTracker,
    required SyncRepository syncRepository,
  })  : _profileCubit = profileCubit,
        _activityCubit = activityCubit,
        _promptToSnapshotBloc = promptToSnapshotBloc,
        _configService = configService,
        _tabVisibility = tabVisibility,
        _syncRepository = syncRepository,
        super(SyncIdle()) {
    // Sync the user's drives on start and periodically.
    createSyncStream();
    restartSyncOnFocus();
    // Sync ArConnect
    createArConnectSyncStream();
    restartArConnectSyncOnFocus();
  }

  /// Waits for the current sync to finish.
  Future<void> waitCurrentSync() async {
    if (state is! SyncIdle) {
      await for (var state in stream) {
        if (state is SyncIdle || state is SyncFailure) {
          break;
        }
      }
    }
  }

  void createSyncStream() async {
    logger.d('Creating sync stream to periodically call sync automatically');

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

    startSync();
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

  Future<void> startSync({bool deepSync = false}) async {
    logger.i('Starting Sync');

    if (state is SyncInProgress) {
      logger.d('Sync state is SyncInProgress, aborting sync...');
      return;
    }

    _syncProgress = SyncProgress.initial();

    try {
      final profile = _profileCubit.state;
      Wallet? wallet;
      String? password;
      SecretKey? cipherKey;

      _initSync = DateTime.now();

      emit(SyncInProgress());
      // Only sync in drives owned by the user if they're logged in.
      logger.d('Checking if user is logged in...');

      if (profile is ProfileLoggedIn) {
        logger.d('User is logged in');

        //Check if profile is ArConnect to skip sync while tab is hidden
        wallet = profile.user.wallet;
        password = profile.user.password;
        cipherKey = profile.user.cipherKey;

        logger.d('Checking if user is from arconnect...');

        final isArConnect = await _profileCubit.isCurrentProfileArConnect();

        logger.d('User using arconnect: $isArConnect');

        if (isArConnect && !_tabVisibility.isTabFocused()) {
          logger.d('Tab hidden, skipping sync...');
          emit(SyncIdle());
          return;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logger.d('Uninterruptible activity in progress, skipping sync...');
          emit(SyncIdle());
          return;
        }

        await _syncRepository.updateUserDrives(
          wallet: wallet,
          password: password,
          cipherKey: profile.user.cipherKey,
        );
      }

      _promptToSnapshotBloc.add(const SyncRunning(isRunning: true));

      await for (var syncProgress in _syncRepository.syncAllDrives(
          wallet: wallet,
          password: password,
          cipherKey: cipherKey,
          syncDeep: deepSync,
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

      if (profile is ProfileLoggedIn) {
        _profileCubit.refreshBalance();
      }

      logger.i('Transaction statuses updated');
    } catch (err, stackTrace) {
      logger.e('Error syncing drives', err, stackTrace);
      addError(err);
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

    emit(SyncIdle());
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
