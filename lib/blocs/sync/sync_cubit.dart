import 'dart:async';
import 'dart:math';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/sync/ghost_folder.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/snapshots/drive_history_composite.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:retry/retry.dart';

import '../../utils/html/html_util.dart';

part 'sync_progress.dart';
part 'sync_state.dart';
part 'utils/add_drive_entity_revisions.dart';
part 'utils/add_file_entity_revisions.dart';
part 'utils/add_folder_entity_revisions.dart';
part 'utils/create_ghosts.dart';
part 'utils/generate_paths.dart';
part 'utils/log_sync.dart';
part 'utils/parse_drive_transactions.dart';
part 'utils/sync_drive.dart';
part 'utils/update_transaction_statuses.dart';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

const kRequiredTxConfirmationCount = 15;
const kRequiredTxConfirmationPendingThreshold = 60 * 8;

const kSyncTimerDuration = 5;
const kArConnectSyncTimerDuration = 2;
const kBlockHeightLookBack = 240;

const _pendingWaitTime = Duration(days: 1);

/// The [SyncCubit] periodically syncs the user's owned and attached drives and their contents.
/// It also checks the status of unconfirmed transactions made by revisions.
class SyncCubit extends Cubit<SyncState> {
  final ProfileCubit _profileCubit;
  final ActivityCubit _activityCubit;
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final Database _db;

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
    required ArweaveService arweave,
    required DriveDao driveDao,
    required Database db,
  })  : _profileCubit = profileCubit,
        _activityCubit = activityCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _db = db,
        super(SyncIdle()) {
    // Sync the user's drives on start and periodically.
    logSync('Building Sync Cubit...');

    createSyncStream();
    restartSyncOnFocus();
    // Sync ArConnect
    createArConnectSyncStream();
    restartArConnectSyncOnFocus();
  }

  void createSyncStream() async {
    logSync('Creating sync stream to periodically call sync automatically');

    await _syncSub?.cancel();

    _syncSub = Stream.periodic(const Duration(minutes: kSyncTimerDuration))
        // Do not start another sync until the previous sync has completed.
        .map((value) => Stream.fromFuture(startSync()))
        .listen((_) {
      logSync('Listening to startSync periodic stream');
    });

    startSync();
  }

  void restartSyncOnFocus() {
    whenBrowserTabIsUnhidden(_restartSync);
  }

  void _restartSync() {
    logSync(
        'Trying to create a sync subscription when window get focused again. This Cubit is active? ${!isClosed}');
    if (_lastSync != null) {
      final minutesSinceLastSync =
          DateTime.now().difference(_lastSync!).inMinutes;
      final isTimerDurationReadyToSync =
          minutesSinceLastSync >= kSyncTimerDuration;

      if (!isTimerDurationReadyToSync) {
        logSync('''
              Can't restart sync when window is focused \n
              Is current active? ${!isClosed} \n
              last sync was $minutesSinceLastSync minutes ago. \n
              It should be $kSyncTimerDuration
              ''');
        return;
      }
    }

    /// This delay is for don't abruptly open the modal when the user is back
    ///  to ArDrive browser tab
    Future.delayed(const Duration(seconds: 2)).then((value) {
      createSyncStream();
    });
  }

  void createArConnectSyncStream() {
    _profileCubit.isCurrentProfileArConnect().then((isArConnect) {
      if (isArConnect) {
        _arconnectSyncSub?.cancel();
        _arconnectSyncSub = Stream.periodic(
                const Duration(minutes: kArConnectSyncTimerDuration))
            // Do not start another sync until the previous sync has completed.
            .map((value) => Stream.fromFuture(arconnectSync()))
            .listen((_) {});
        arconnectSync();
      }
    });
  }

  Future<void> arconnectSync() async {
    if (!isBrowserTabHidden() && await _profileCubit.logoutIfWalletMismatch()) {
      emit(SyncWalletMismatch());
      return;
    }
  }

  void restartArConnectSyncOnFocus() async {
    if (await _profileCubit.isCurrentProfileArConnect()) {
      whenBrowserTabIsUnhidden(() {
        Future.delayed(const Duration(seconds: 2))
            .then((value) => createArConnectSyncStream());
      });
    }
  }

  var ghostFolders = <FolderID, GhostFolder>{};

  Future<void> startSync({bool syncDeep = false}) async {
    logSync('Starting Sync');
    logSync('SyncCubit is currently active? ${!isClosed}');

    if (state is SyncInProgress) {
      logSync('Sync state is SyncInProgress, aborting sync...');
      return;
    }

    _syncProgress = SyncProgress.initial();

    try {
      final profile = _profileCubit.state;
      String? ownerAddress;

      _initSync = DateTime.now();

      logSync('Emitting SyncInProgress state');

      emit(SyncInProgress());
      // Only sync in drives owned by the user if they're logged in.
      logSync('Checking if user is logged in...');

      if (profile is ProfileLoggedIn) {
        logSync('User is logged in');

        //Check if profile is ArConnect to skip sync while tab is hidden
        ownerAddress = profile.walletAddress;

        logSync('Checking if user is from ar connect...');

        final isArConnect = await _profileCubit.isCurrentProfileArConnect();

        logSync('User is ar connect? $isArConnect');

        if (isArConnect && isBrowserTabHidden()) {
          logSync('Tab hidden, skipping sync...');
          emit(SyncIdle());
          return;
        }

        if (_activityCubit.state is ActivityInProgress) {
          logSync('Uninterruptible activity in progress, skipping sync...');
          emit(SyncIdle());
          return;
        }

        // This syncs in the latest info on drives owned by the user and will be overwritten
        // below when the full sync process is ran.
        //
        // It also adds the encryption keys onto the drive models which isn't touched by the
        // later system.
        final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
          profile.wallet,
          profile.password,
        );

        await _driveDao.updateUserDrives(userDriveEntities, profile.cipherKey);
      }

      // Sync the contents of each drive attached in the app.
      final drives = await _driveDao.allDrives().map((d) => d).get();

      if (drives.isEmpty) {
        _syncProgress = SyncProgress.emptySyncCompleted();

        syncProgressController.add(_syncProgress);

        emit(SyncIdle());

        return;
      }

      final currentBlockHeight = await retry(
        () async => await _arweave.getCurrentBlockHeight(),
        onRetry: (exception) => logSync(
          'Retrying for get the current block height on exception ${exception.toString()}',
        ),
      );

      _syncProgress = _syncProgress.copyWith(drivesCount: drives.length);
      logSync('Current block height number $currentBlockHeight');
      final driveSyncProcesses = drives.map(
        (drive) => _syncDrive(
          drive.id,
          driveDao: _driveDao,
          arweaveService: _arweave,
          ghostFolders: ghostFolders,
          database: _db,
          profileState: profile,
          addError: addError,
          lastBlockHeight: syncDeep
              ? 0
              : calculateSyncLastBlockHeight(drive.lastBlockHeight!),
          currentBlockHeight: currentBlockHeight,
          transactionParseBatchSize:
              200 ~/ (_syncProgress.drivesCount - _syncProgress.drivesSynced),
        ).handleError(
          (error, stackTrace) {
            logSync('''
                    Error syncing drive with id ${drive.id}. \n
                    Skipping sync on this drive.\n
                    Exception: \n
                    ${error.toString()} \n
                    StackTrace: \n
                    ${stackTrace.toString()}
                    ''');
            addError(error!);
          },
        ),
      );

      double totalProgress = 0;
      await Future.wait(
        driveSyncProcesses.map(
          (driveSyncProgress) async {
            double currentDriveProgress = 0;
            await for (var driveProgress in driveSyncProgress) {
              currentDriveProgress =
                  (totalProgress + driveProgress) / drives.length;
              if (currentDriveProgress > _syncProgress.progress) {
                _syncProgress = _syncProgress.copyWith(
                  progress: currentDriveProgress,
                );
              }
              syncProgressController.add(_syncProgress);
            }
            totalProgress += 1;
            _syncProgress = _syncProgress.copyWith(
              drivesSynced: _syncProgress.drivesSynced + 1,
              progress: totalProgress / drives.length,
            );
            syncProgressController.add(_syncProgress);
          },
        ),
      );

      logSync('Creating ghosts...');

      await createGhosts(
        driveDao: _driveDao,
        ownerAddress: ownerAddress,
        ghostFolders: ghostFolders,
      );

      ghostFolders.clear();

      logSync('Ghosts created...');

      logSync('Updating transaction statuses...');

      await Future.wait([
        if (profile is ProfileLoggedIn) _profileCubit.refreshBalance(),
        _updateTransactionStatuses(
          driveDao: _driveDao,
          arweave: _arweave,
        ),
      ]);

      logSync('Transaction statuses updated');

      logSync(
          'Syncing drives finished.\nDrives quantity: ${_syncProgress.drivesCount}\n'
          'The total progress was ${(_syncProgress.progress * 100).roundToDouble()}');
    } catch (err, stackTrace) {
      logSyncError(err, stackTrace);
      addError(err);
    }
    _lastSync = DateTime.now();

    logSync('The sync process took: '
        '${_lastSync!.difference(_initSync).inMilliseconds} milliseconds to finish.\n');

    emit(SyncIdle());
  }

  int calculateSyncLastBlockHeight(int lastBlockHeight) {
    logSync('Last Block Height: $lastBlockHeight');
    if (_lastSync != null) {
      return lastBlockHeight;
    } else {
      return max(lastBlockHeight - kBlockHeightLookBack, 0);
    }
  }

  // Exposing this for use by create folder functions since they need to update
  // folder tree
  Future<void> generateFsEntryPaths(
    String driveId,
    Map<String, FolderEntriesCompanion> foldersByIdMap,
    Map<String, FileEntriesCompanion> filesByIdMap,
  ) async {
    print('Generating fs entry paths...');
    ghostFolders = await _generateFsEntryPaths(
      ghostFolders: ghostFolders,
      driveDao: _driveDao,
      driveId: driveId,
      foldersByIdMap: foldersByIdMap,
      filesByIdMap: filesByIdMap,
    );
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    logSyncError(error, stackTrace);
    logSync('Emitting SyncFailure state');
    if (isClosed) {
      return;
    }
    emit(SyncFailure(error: error, stackTrace: stackTrace));

    logSync('Emitting SyncIdle state');
    emit(SyncIdle());
    super.onError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    logSync('Closing SyncCubit...');
    await _syncSub?.cancel();
    await _arconnectSyncSub?.cancel();
    await closeVisibilityChangeStream();
    await super.close();
  }
}
