import 'dart:async';
import 'dart:math';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/blocs/sync/ghost_folder.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/license/license_types.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive/utils/snapshots/drive_history_composite.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:retry/retry.dart';

part 'sync_progress.dart';
part 'sync_state.dart';
part 'utils/add_drive_entity_revisions.dart';
part 'utils/add_file_entity_revisions.dart';
part 'utils/add_folder_entity_revisions.dart';
part 'utils/create_ghosts.dart';
part 'utils/generate_paths.dart';
part 'utils/get_all_file_entities.dart';
part 'utils/parse_drive_transactions.dart';
part 'utils/sync_drive.dart';
part 'utils/update_licenses.dart';
part 'utils/update_transaction_statuses.dart';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

const kRequiredTxConfirmationPendingThreshold = 60 * 8;

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
  final TabVisibilitySingleton _tabVisibility;
  final ConfigService _configService;
  final LicenseService _licenseService;

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
    required ArweaveService arweave,
    required DriveDao driveDao,
    required Database db,
    required TabVisibilitySingleton tabVisibility,
    required ConfigService configService,
    required LicenseService licenseService,
    required ActivityTracker activityTracker,
  })  : _profileCubit = profileCubit,
        _activityCubit = activityCubit,
        _arweave = arweave,
        _driveDao = driveDao,
        _db = db,
        _configService = configService,
        _licenseService = licenseService,
        _tabVisibility = tabVisibility,
        super(SyncIdle()) {
    // Sync the user's drives on start and periodically.
    createSyncStream();
    restartSyncOnFocus();
    // Sync ArConnect
    createArConnectSyncStream();
    restartArConnectSyncOnFocus();
  }

  void createSyncStream() async {
    logger.d('Creating sync stream to periodically call sync automatically');

    await _syncSub?.cancel();

    _syncSub = Stream.periodic(
            Duration(seconds: _configService.config.autoSyncIntervalInSeconds))
        // Do not start another sync until the previous sync has completed.
        .map((value) => Stream.fromFuture(startSync()))
        .listen((_) {
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
        'Trying to create a sync subscription when window get focused again. This Cubit is active? ${!isClosed}');
    if (_lastSync != null) {
      final syncInterval = _configService.config.autoSyncIntervalInSeconds;
      final minutesSinceLastSync =
          DateTime.now().difference(_lastSync!).inSeconds;
      final isTimerDurationReadyToSync = minutesSinceLastSync >= syncInterval;

      if (!isTimerDurationReadyToSync) {
        logger.d(
            "Can't restart sync when window is focused. Is current active? ${!isClosed}. Last sync was $minutesSinceLastSync seconds ago. It should be $syncInterval.");

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

  Future<void> startSync({bool syncDeep = false}) async {
    logger.i('Starting Sync');

    if (state is SyncInProgress) {
      logger.d('Sync state is SyncInProgress, aborting sync...');
      return;
    }

    _syncProgress = SyncProgress.initial();

    try {
      final profile = _profileCubit.state;
      String? ownerAddress;

      _initSync = DateTime.now();

      emit(SyncInProgress());
      // Only sync in drives owned by the user if they're logged in.
      logger.d('Checking if user is logged in...');

      if (profile is ProfileLoggedIn) {
        logger.d('User is logged in');

        //Check if profile is ArConnect to skip sync while tab is hidden
        ownerAddress = profile.walletAddress;

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
        _lastSync = DateTime.now();

        emit(SyncIdle());

        return;
      }

      final currentBlockHeight = await retry(
        () async => await _arweave.getCurrentBlockHeight(),
        onRetry: (exception) => logger.w(
          'Retrying for get the current block height',
        ),
      );

      _syncProgress = _syncProgress.copyWith(drivesCount: drives.length);
      logger.d('Current block height number $currentBlockHeight');
      final driveSyncProcesses = drives.map(
        (drive) async* {
          try {
            yield* _syncDrive(
              drive.id,
              driveDao: _driveDao,
              arweave: _arweave,
              ghostFolders: ghostFolders,
              database: _db,
              profileState: profile,
              addError: addError,
              lastBlockHeight: syncDeep
                  ? 0
                  : calculateSyncLastBlockHeight(drive.lastBlockHeight!),
              currentBlockHeight: currentBlockHeight,
              transactionParseBatchSize: 200 ~/
                  (_syncProgress.drivesCount - _syncProgress.drivesSynced),
              ownerAddress: drive.ownerAddress,
              configService: _configService,
            );
          } catch (error, stackTrace) {
            logger.e(
              'Error syncing drive with id ${drive.id}. Skipping sync on this drive',
              error,
              stackTrace,
            );

            addError(error);
          }
        },
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

      logger.i('Creating ghosts...');

      await createGhosts(
        driveDao: _driveDao,
        ownerAddress: ownerAddress,
        ghostFolders: ghostFolders,
      );

      ghostFolders.clear();

      logger.i('Ghosts created...');

      logger.i('Updating transaction statuses...');

      final allFileRevisions = await _getAllFileEntities(driveDao: _driveDao);
      final metadataTxsFromSnapshots =
          await SnapshotItemOnChain.getAllCachedTransactionIds();

      final confirmedFileTxIds = allFileRevisions
          .where((file) => metadataTxsFromSnapshots.contains(file.metadataTxId))
          .map((file) => file.dataTxId)
          .toList();

      final licenseTxIds = <String>{};
      final revisionsToSyncLicense = (await _driveDao
          .allFileRevisionsWithLicenseReferencedButNotSynced()
          .get())
        ..retainWhere((rev) => licenseTxIds.add(rev.licenseTxId!));

      await Future.wait(
        [
          if (profile is ProfileLoggedIn) _profileCubit.refreshBalance(),
          _updateTransactionStatuses(
            driveDao: _driveDao,
            arweave: _arweave,
            txsIdsToSkip: confirmedFileTxIds,
          ),
          _updateLicenses(
            driveDao: _driveDao,
            arweave: _arweave,
            licenseService: _licenseService,
            revisionsToSyncLicense: revisionsToSyncLicense,
          ),
        ],
      );

      logger.i('Transaction statuses updated');
    } catch (err, stackTrace) {
      logger.e('Error syncing drives', err, stackTrace);
      addError(err);
    }
    _lastSync = DateTime.now();

    logger.i(
        'Syncing drives finished. Drives quantity: ${_syncProgress.drivesCount}. The total progress was ${(_syncProgress.progress * 100).roundToDouble()}%. The sync process took: ${_lastSync!.difference(_initSync).inMilliseconds}ms to finish');

    emit(SyncIdle());
  }

  int calculateSyncLastBlockHeight(int lastBlockHeight) {
    logger.d('Calculating sync last block height: $lastBlockHeight');
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
    logger.i('Generating fs entry paths...');
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
    logger.e('An error occured on SyncCubit', error, stackTrace);
    if (isClosed) {
      return;
    }
    emit(SyncFailure(error: error, stackTrace: stackTrace));

    logger.d('SyncCubit error emitted');
    emit(SyncIdle());
    super.onError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    logger.d('Closing SyncCubit...');
    await _syncSub?.cancel();
    await _arconnectSyncSub?.cancel();
    await _restartOnFocusStreamSubscription?.cancel();
    await _restartArConnectOnFocusStreamSubscription?.cancel();

    _syncSub = null;
    _arconnectSyncSub = null;
    _restartOnFocusStreamSubscription = null;
    _restartArConnectOnFocusStreamSubscription = null;

    await super.close();

    logger.d('SyncCubit closed');
  }
}
