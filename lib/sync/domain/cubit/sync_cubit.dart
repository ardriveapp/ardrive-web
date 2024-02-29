import 'dart:async';
import 'dart:math';

import 'package:ardrive/blocs/activity/activity_cubit.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_event.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_composed.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/sync/domain/ghost_folder.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/utils/logger.dart';
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

part 'sync_state.dart';

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
  final PromptToSnapshotBloc _promptToSnapshotBloc;
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
    required PromptToSnapshotBloc promptToSnapshotBloc,
    required ArweaveService arweave,
    required DriveDao driveDao,
    required Database db,
    required TabVisibilitySingleton tabVisibility,
    required ConfigService configService,
    required LicenseService licenseService,
    required ActivityTracker activityTracker,
  })  : _profileCubit = profileCubit,
        _activityCubit = activityCubit,
        _promptToSnapshotBloc = promptToSnapshotBloc,
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
      'Attempting to create a sync subscription when the window regains focus.'
      ' Is Cubit active? ${!isClosed}',
    );

    if (_lastSync != null) {
      final syncInterval = _configService.config.autoSyncIntervalInSeconds;
      final minutesSinceLastSync =
          DateTime.now().difference(_lastSync!).inSeconds;
      final isTimerDurationReadyToSync = minutesSinceLastSync >= syncInterval;

      if (!isTimerDurationReadyToSync) {
        logger.d(
          'Cannot restart sync when the window is focused. Is it currently'
          ' active? ${!isClosed}.'
          ' Last sync occurred $minutesSinceLastSync seconds ago, but it'
          ' should be at least $syncInterval seconds.',
        );

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

      _promptToSnapshotBloc.add(const SyncRunning(isRunning: true));

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
              promptToSnapshotBloc: _promptToSnapshotBloc,
            );
          } catch (error, stackTrace) {
            logger.e(
              'Error syncing drive. Skipping sync on this drive',
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

      logger.i('Syncing licenses...');

      final licenseTxIds = <String>{};
      final revisionsToSyncLicense = (await _driveDao
          .allFileRevisionsWithLicenseReferencedButNotSynced()
          .get())
        ..retainWhere((rev) => licenseTxIds.add(rev.licenseTxId!));

      logger.d('Found ${revisionsToSyncLicense.length} licenses to sync');

      _updateLicenses(
        driveDao: _driveDao,
        arweave: _arweave,
        licenseService: _licenseService,
        revisionsToSyncLicense: revisionsToSyncLicense,
      );

      logger.i('Licenses synced');

      logger.i('Updating transaction statuses...');

      final allFileRevisions = await _getAllFileEntities(driveDao: _driveDao);
      final metadataTxsFromSnapshots =
          await SnapshotItemOnChain.getAllCachedTransactionIds();

      final confirmedFileTxIds = allFileRevisions
          .where((file) => metadataTxsFromSnapshots.contains(file.metadataTxId))
          .map((file) => file.dataTxId)
          .toList();

      await Future.wait(
        [
          if (profile is ProfileLoggedIn) _profileCubit.refreshBalance(),
          _updateTransactionStatuses(
            driveDao: _driveDao,
            arweave: _arweave,
            txsIdsToSkip: confirmedFileTxIds,
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
      'Syncing drives finished. Drives quantity: ${_syncProgress.drivesCount}.'
      ' The total progress was'
      ' ${(_syncProgress.progress * 100).roundToDouble()}%.'
      ' The sync process took:'
      ' ${_lastSync!.difference(_initSync).inMilliseconds}ms to finish',
    );

    _promptToSnapshotBloc.add(const SyncRunning(isRunning: false));
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
      logger.d('SyncCubit is closed, aborting onError...');
      return;
    }

    emit(SyncFailure(error: error, stackTrace: stackTrace));

    emit(SyncIdle());
    super.onError(error, stackTrace);
  }

  @override
  Future<void> close() async {
    logger.d('Closing SyncCubit instance');
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

/// Computes the new drive revisions from the provided entities, inserts them into the database,
/// and returns the latest revision.
Future<DriveRevisionsCompanion?> _addNewDriveEntityRevisions({
  required DriveDao driveDao,
  required Database database,
  required Iterable<DriveEntity> newEntities,
}) async {
  DriveRevisionsCompanion? latestRevision;

  final newRevisions = <DriveRevisionsCompanion>[];
  for (final entity in newEntities) {
    latestRevision ??= await driveDao
        .latestDriveRevisionByDriveId(driveId: entity.id!)
        .getSingleOrNull()
        .then((r) => r?.toCompanion(true));

    final revisionPerformedAction =
        entity.getPerformedRevisionAction(latestRevision);
    if (revisionPerformedAction == null) {
      continue;
    }
    final revision =
        entity.toRevisionCompanion(performedAction: revisionPerformedAction);

    if (revision.action.value.isEmpty) {
      continue;
    }

    newRevisions.add(revision);
    latestRevision = revision;
  }

  await database.batch((b) {
    b.insertAllOnConflictUpdate(database.driveRevisions, newRevisions);
    b.insertAllOnConflictUpdate(
      database.networkTransactions,
      newRevisions
          .map(
            (rev) => NetworkTransactionsCompanion.insert(
              transactionDateCreated: rev.dateCreated,
              id: rev.metadataTxId.value,
              status: const Value(TransactionStatus.confirmed),
            ),
          )
          .toList(),
    );
  });

  return latestRevision;
}

/// Computes the refreshed drive entries from the provided revisions and returns them as a map keyed by their ids.
Future<DrivesCompanion> _computeRefreshedDriveFromRevision({
  required DriveDao driveDao,
  required DriveRevisionsCompanion latestRevision,
}) async {
  final oldestRevision = await driveDao
      .oldestDriveRevisionByDriveId(driveId: latestRevision.driveId.value)
      .getSingleOrNull();

  return latestRevision.toEntryCompanion().copyWith(
        dateCreated: Value(
          oldestRevision?.dateCreated ?? latestRevision.dateCreated as DateTime,
        ),
      );
}

/// Computes the new file revisions from the provided entities, inserts them into the database,
/// and returns only the latest revisions.
Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions({
  required DriveDao driveDao,
  required Database database,
  required String driveId,
  required Iterable<FileEntity> newEntities,
}) async {
  // The latest file revisions, keyed by their entity ids.
  final latestRevisions = <String, FileRevisionsCompanion>{};

  final newRevisions = <FileRevisionsCompanion>[];
  for (final entity in newEntities) {
    if (!latestRevisions.containsKey(entity.id) &&
        entity.parentFolderId != null) {
      final revisions = await driveDao
          .latestFileRevisionByFileId(driveId: driveId, fileId: entity.id!)
          .getSingleOrNull();
      if (revisions != null) {
        latestRevisions[entity.id!] = revisions.toCompanion(true);
      }
    }

    final revisionPerformedAction =
        entity.getPerformedRevisionAction(latestRevisions[entity.id]);
    if (revisionPerformedAction == null) {
      continue;
    }
    // If Parent-Folder-Id is missing for a file, put it in the root folder
    try {
      entity.parentFolderId = entity.parentFolderId ?? rootPath;
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value.isEmpty) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id!] = revision;
    } catch (e, stacktrace) {
      logger.e('Error adding revision for entity', e, stacktrace);
    }
  }

  await database.batch((b) {
    b.insertAllOnConflictUpdate(database.fileRevisions, newRevisions);
    b.insertAllOnConflictUpdate(
        database.networkTransactions,
        newRevisions
            .expand(
              (rev) => [
                NetworkTransactionsCompanion.insert(
                  transactionDateCreated: rev.dateCreated,
                  id: rev.metadataTxId.value,
                  status: const Value(TransactionStatus.confirmed),
                ),
                // We cannot be sure that the data tx of files have been mined
                // so we'll mark it as pending initially.
                NetworkTransactionsCompanion.insert(
                  transactionDateCreated: rev.dateCreated,
                  id: rev.dataTxId.value,
                  status: const Value(TransactionStatus.pending),
                ),
              ],
            )
            .toList());
  });

  return latestRevisions.values.toList();
}

/// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
Future<Map<String, FileEntriesCompanion>>
    _computeRefreshedFileEntriesFromRevisions({
  required DriveDao driveDao,
  required String driveId,
  required List<FileRevisionsCompanion> revisionsByFileId,
}) async {
  final updatedFilesById = {
    for (final revision in revisionsByFileId)
      revision.fileId.value: revision.toEntryCompanion(),
  };

  for (final fileId in updatedFilesById.keys) {
    final oldestRevision = await driveDao
        .oldestFileRevisionByFileId(driveId: driveId, fileId: fileId)
        .getSingleOrNull();

    final dateCreated = oldestRevision?.dateCreated ??
        updatedFilesById[fileId]!.dateCreated.value;

    updatedFilesById[fileId] = updatedFilesById[fileId]!.copyWith(
      dateCreated: Value<DateTime>(dateCreated),
    );
  }

  return updatedFilesById;
}

/// Computes the new folder revisions from the provided entities, inserts them into the database,
/// and returns only the latest revisions.
Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions({
  required DriveDao driveDao,
  required Database database,
  required String driveId,
  required Iterable<FolderEntity> newEntities,
}) async {
  // The latest folder revisions, keyed by their entity ids.
  final latestRevisions = <String, FolderRevisionsCompanion>{};

  final newRevisions = <FolderRevisionsCompanion>[];
  for (final entity in newEntities) {
    if (!latestRevisions.containsKey(entity.id)) {
      final revisions = (await driveDao
          .latestFolderRevisionByFolderId(
              driveId: driveId, folderId: entity.id!)
          .getSingleOrNull());
      if (revisions != null) {
        latestRevisions[entity.id!] = revisions.toCompanion(true);
      }
    }

    final revisionPerformedAction =
        entity.getPerformedRevisionAction(latestRevisions[entity.id]);
    if (revisionPerformedAction == null) {
      continue;
    }
    final revision =
        entity.toRevisionCompanion(performedAction: revisionPerformedAction);

    if (revision.action.value.isEmpty) {
      continue;
    }

    newRevisions.add(revision);
    latestRevisions[entity.id!] = revision;
  }

  await database.batch((b) {
    b.insertAllOnConflictUpdate(database.folderRevisions, newRevisions);
    b.insertAllOnConflictUpdate(
        database.networkTransactions,
        newRevisions
            .map(
              (rev) => NetworkTransactionsCompanion.insert(
                transactionDateCreated: rev.dateCreated,
                id: rev.metadataTxId.value,
                status: const Value(TransactionStatus.confirmed),
              ),
            )
            .toList());
  });

  return latestRevisions.values.toList();
}

/// Computes the refreshed folder entries from the provided revisions and returns them as a map keyed by their ids.
Future<Map<String, FolderEntriesCompanion>>
    _computeRefreshedFolderEntriesFromRevisions({
  required DriveDao driveDao,
  required String driveId,
  required List<FolderRevisionsCompanion> revisionsByFolderId,
}) async {
  final updatedFoldersById = {
    for (final revision in revisionsByFolderId)
      revision.folderId.value: revision.toEntryCompanion(),
  };

  for (final folderId in updatedFoldersById.keys) {
    final oldestRevision = await driveDao
        .oldestFolderRevisionByFolderId(driveId: driveId, folderId: folderId)
        .getSingleOrNull();

    final dateCreated = oldestRevision?.dateCreated ??
        updatedFoldersById[folderId]!.dateCreated.value;

    updatedFoldersById[folderId] = updatedFoldersById[folderId]!.copyWith(
      dateCreated: Value<DateTime>(dateCreated),
    );
  }

  return updatedFoldersById;
}

Future<void> createGhosts({
  required DriveDao driveDao,
  required Map<FolderID, GhostFolder> ghostFolders,
  String? ownerAddress,
}) async {
  final ghostFoldersByDrive =
      <DriveID, Map<FolderID, FolderEntriesCompanion>>{};
  //Finalize missing parent list
  for (final ghostFolder in ghostFolders.values) {
    final folder = await driveDao
        .folderById(
          driveId: ghostFolder.driveId,
          folderId: ghostFolder.folderId,
        )
        .getSingleOrNull();

    final folderExists = folder != null;

    if (folderExists) {
      continue;
    }

    // Add to database
    final drive =
        await driveDao.driveById(driveId: ghostFolder.driveId).getSingle();

    // Don't create ghost folder if the ghost is a missing root folder
    // Or if the drive doesn't belong to the user
    final isReadOnlyDrive = drive.ownerAddress != ownerAddress;
    final isRootFolderGhost = drive.rootFolderId == ghostFolder.folderId;

    if (isReadOnlyDrive || isRootFolderGhost) {
      continue;
    }

    final folderEntry = FolderEntry(
      id: ghostFolder.folderId,
      driveId: drive.id,
      parentFolderId: drive.rootFolderId,
      name: ghostFolder.folderId,
      path: rootPath,
      lastUpdated: DateTime.now(),
      isGhost: true,
      dateCreated: DateTime.now(),
      isHidden: ghostFolder.isHidden,
    );
    await driveDao.into(driveDao.folderEntries).insert(folderEntry);
    ghostFoldersByDrive.putIfAbsent(
      drive.id,
      () => {folderEntry.id: folderEntry.toCompanion(false)},
    );
  }
  await Future.wait(
    [
      ...ghostFoldersByDrive.entries.map((entry) => _generateFsEntryPaths(
          driveDao: driveDao,
          driveId: entry.key,
          foldersByIdMap: entry.value,
          ghostFolders: ghostFolders,
          filesByIdMap: {})),
    ],
  );
}

/// Generates paths for the folders (and their children) and files provided.
Future<Map<FolderID, GhostFolder>> _generateFsEntryPaths({
  required DriveDao driveDao,
  required String driveId,
  required Map<String, FolderEntriesCompanion> foldersByIdMap,
  required Map<String, FileEntriesCompanion> filesByIdMap,
  required Map<FolderID, GhostFolder> ghostFolders,
}) async {
  final staleFolderTree = <FolderNode>[];
  for (final folder in foldersByIdMap.values) {
    // Get trees of the updated folders and files for path generation.
    final tree = await driveDao.getFolderTree(driveId, folder.id.value);

    // Remove any trees that are a subset of another.
    var newTreeIsSubsetOfExisting = false;
    var newTreeIsSupersetOfExisting = false;
    for (final existingTree in staleFolderTree) {
      if (existingTree.searchForFolder(tree.folder.id) != null) {
        newTreeIsSubsetOfExisting = true;
      } else if (tree.searchForFolder(existingTree.folder.id) != null) {
        staleFolderTree.remove(existingTree);
        staleFolderTree.add(tree);
        newTreeIsSupersetOfExisting = true;
      }
    }

    if (!newTreeIsSubsetOfExisting && !newTreeIsSupersetOfExisting) {
      staleFolderTree.add(tree);
    }
  }

  Future<void> addMissingFolder(String folderId) async {
    ghostFolders.putIfAbsent(
        folderId, () => GhostFolder(folderId: folderId, driveId: driveId));
  }

  Future<void> updateFolderTree(FolderNode node, String parentPath) async {
    final folderId = node.folder.id;
    // If this is the root folder, we should not include its name as part of the path.
    final folderPath = node.folder.parentFolderId != null
        ? '$parentPath/${node.folder.name}'
        : rootPath;

    await driveDao
        .updateFolderById(driveId, folderId)
        .write(FolderEntriesCompanion(path: Value(folderPath)));

    for (final staleFileId in node.files.keys) {
      final filePath = '$folderPath/${node.files[staleFileId]!.name}';

      await driveDao
          .updateFileById(driveId, staleFileId)
          .write(FileEntriesCompanion(path: Value(filePath)));
    }

    for (final staleFolder in node.subfolders) {
      await updateFolderTree(staleFolder, folderPath);
    }
  }

  for (final treeRoot in staleFolderTree) {
    // Get the path of this folder's parent.
    String? parentPath;
    if (treeRoot.folder.parentFolderId == null) {
      parentPath = rootPath;
    } else {
      parentPath = (await driveDao
          .folderById(
              driveId: driveId, folderId: treeRoot.folder.parentFolderId!)
          .map((f) => f.path)
          .getSingleOrNull());
    }
    if (parentPath != null) {
      await updateFolderTree(treeRoot, parentPath);
    } else {
      await addMissingFolder(
        treeRoot.folder.parentFolderId!,
      );
    }
  }

  // Update paths of files whose parent folders were not updated.
  final staleOrphanFiles = filesByIdMap.values
      .where((f) => !foldersByIdMap.containsKey(f.parentFolderId));
  for (final staleOrphanFile in staleOrphanFiles) {
    if (staleOrphanFile.parentFolderId.value.isNotEmpty) {
      final parentPath = await driveDao
          .folderById(
              driveId: driveId, folderId: staleOrphanFile.parentFolderId.value)
          .map((f) => f.path)
          .getSingleOrNull();

      if (parentPath != null) {
        final filePath = '$parentPath/${staleOrphanFile.name.value}';

        await driveDao.writeToFile(FileEntriesCompanion(
            id: staleOrphanFile.id,
            driveId: staleOrphanFile.driveId,
            path: Value(filePath)));
      } else {
        logger.d(
            'Add missing folder to file with id ${staleOrphanFile.parentFolderId}');

        await addMissingFolder(
          staleOrphanFile.parentFolderId.value,
        );
      }
    }
  }
  return ghostFolders;
}

Future<List<FileRevision>> _getAllFileEntities({
  required DriveDao driveDao,
}) async {
  return await driveDao.db.fileRevisions.select().get();
}

/// Process the transactions from the first phase into database entities.
/// This is done in batches to improve performance and provide more granular progress
Stream<double> _parseDriveTransactionsIntoDatabaseEntities({
  required DriveDao driveDao,
  required Database database,
  required ArweaveService arweave,
  required List<DriveHistoryTransaction> transactions,
  required Drive drive,
  required SecretKey? driveKey,
  required int lastBlockHeight,
  required int currentBlockHeight,
  required int batchSize,
  required SnapshotDriveHistory snapshotDriveHistory,
  required Map<FolderID, GhostFolder> ghostFolders,
  required String ownerAddress,
}) async* {
  final numberOfDriveEntitiesToParse = transactions.length;
  var numberOfDriveEntitiesParsed = 0;

  double driveEntityParseProgress() =>
      numberOfDriveEntitiesParsed / numberOfDriveEntitiesToParse;

  if (transactions.isEmpty) {
    await driveDao.writeToDrive(
      DrivesCompanion(
        id: Value(drive.id),
        lastBlockHeight: Value(currentBlockHeight),
        syncCursor: const Value(null),
      ),
    );

    /// If there's nothing to sync, we assume that all were synced

    yield 1;
    return;
  }

  logger.d(
    'no. of entities in drive with id ${drive.id} to be parsed are: $numberOfDriveEntitiesToParse\n',
  );

  yield* _batchProcess<DriveHistoryTransaction>(
      list: transactions,
      batchSize: batchSize,
      endOfBatchCallback: (items) async* {
        final isReadingFromSnapshot = snapshotDriveHistory.items.isNotEmpty;

        if (!isReadingFromSnapshot) {
          logger.d('Getting metadata from drive ${drive.id}');
        }

        final entityHistory =
            await arweave.createDriveEntityHistoryFromTransactions(
          items,
          driveKey,
          lastBlockHeight,
          driveId: drive.id,
          ownerAddress: ownerAddress,
        );

        // Create entries for all the new revisions of file and folders in this drive.
        final newEntities = entityHistory.blockHistory
            .map((b) => b.entities)
            .expand((entities) => entities);

        numberOfDriveEntitiesParsed += items.length - newEntities.length;

        yield driveEntityParseProgress();

        // Handle the last page of newEntities, i.e; There's nothing more to sync
        if (newEntities.length < batchSize) {
          // Reset the sync cursor after every sync to pick up files from other instances of the app.
          // (Different tab, different window, mobile, desktop etc)
          await driveDao.writeToDrive(DrivesCompanion(
            id: Value(drive.id),
            lastBlockHeight: Value(currentBlockHeight),
            syncCursor: const Value(null),
          ));
        }

        await database.transaction(() async {
          final latestDriveRevision = await _addNewDriveEntityRevisions(
            driveDao: driveDao,
            database: database,
            newEntities: newEntities.whereType<DriveEntity>(),
          );
          final latestFolderRevisions = await _addNewFolderEntityRevisions(
            driveDao: driveDao,
            database: database,
            driveId: drive.id,
            newEntities: newEntities.whereType<FolderEntity>(),
          );
          final latestFileRevisions = await _addNewFileEntityRevisions(
            driveDao: driveDao,
            database: database,
            driveId: drive.id,
            newEntities: newEntities.whereType<FileEntity>(),
          );

          // Check and handle cases where there's no more revisions
          final updatedDrive = latestDriveRevision != null
              ? await _computeRefreshedDriveFromRevision(
                  driveDao: driveDao,
                  latestRevision: latestDriveRevision,
                )
              : null;

          final updatedFoldersById =
              await _computeRefreshedFolderEntriesFromRevisions(
            driveDao: driveDao,
            driveId: drive.id,
            revisionsByFolderId: latestFolderRevisions,
          );
          final updatedFilesById =
              await _computeRefreshedFileEntriesFromRevisions(
            driveDao: driveDao,
            driveId: drive.id,
            revisionsByFileId: latestFileRevisions,
          );

          numberOfDriveEntitiesParsed += newEntities.length;

          numberOfDriveEntitiesParsed -=
              updatedFoldersById.length + updatedFilesById.length;

          // Update the drive model, making sure to not overwrite the existing keys defined on the drive.
          if (updatedDrive != null) {
            await (database.update(database.drives)
                  ..whereSamePrimaryKey(updatedDrive))
                .write(updatedDrive);
          }

          // Update the folder and file entries before generating their new paths.
          await database.batch((b) {
            b.insertAllOnConflictUpdate(
                database.folderEntries, updatedFoldersById.values.toList());
            b.insertAllOnConflictUpdate(
                database.fileEntries, updatedFilesById.values.toList());
          });

          await _generateFsEntryPaths(
            ghostFolders: ghostFolders,
            driveDao: driveDao,
            driveId: drive.id,
            foldersByIdMap: updatedFoldersById,
            filesByIdMap: updatedFilesById,
          );

          numberOfDriveEntitiesParsed +=
              updatedFoldersById.length + updatedFilesById.length;
        });
        yield driveEntityParseProgress();
      });

  logger.i(
      'drive: ${drive.id} sync completed. no. of transactions to be parsed into entities: $numberOfDriveEntitiesToParse. no. of parsed entities: $numberOfDriveEntitiesParsed');
}

Stream<double> _batchProcess<T>({
  required List<T> list,
  required Stream<double> Function(List<T> items) endOfBatchCallback,
  required int batchSize,
}) async* {
  if (list.isEmpty) {
    return;
  }

  final length = list.length;

  for (var i = 0; i < length / batchSize; i++) {
    final currentBatch = <T>[];

    /// Mounts the list to be iterated
    for (var j = i * batchSize; j < ((i + 1) * batchSize); j++) {
      if (j >= length) {
        break;
      }

      currentBatch.add(list[j]);
    }

    yield* endOfBatchCallback(currentBatch);
  }
}

const fetchPhaseWeight = 0.1;
const parsePhaseWeight = 0.9;

Stream<double> _syncDrive(
  String driveId, {
  required DriveDao driveDao,
  required ProfileState profileState,
  required ArweaveService arweave,
  required Database database,
  required Function addError,
  required int currentBlockHeight,
  required int lastBlockHeight,
  required int transactionParseBatchSize,
  required Map<FolderID, GhostFolder> ghostFolders,
  required String ownerAddress,
  required ConfigService configService,
  required PromptToSnapshotBloc promptToSnapshotBloc,
}) async* {
  /// Variables to count the current drive's progress information
  final drive = await driveDao.driveById(driveId: driveId).getSingle();
  final startSyncDT = DateTime.now();

  logger.i('Syncing drive: ${drive.id}');

  SecretKey? driveKey;

  if (drive.isPrivate) {
    // Only sync private drives when the user is logged in.
    if (profileState is ProfileLoggedIn) {
      driveKey = await driveDao.getDriveKey(drive.id, profileState.cipherKey);
    } else {
      driveKey = await driveDao.getDriveKeyFromMemory(drive.id);
      if (driveKey == null) {
        throw StateError('Drive key not found');
      }
    }
  }
  final fetchPhaseStartDT = DateTime.now();

  logger.d('Fetching all transactions for drive ${drive.id}');

  final transactions = <DriveHistoryTransaction>[];

  List<SnapshotItem> snapshotItems = [];

  if (configService.config.enableSyncFromSnapshot) {
    logger.i('Syncing from snapshot: ${drive.id}');

    final snapshotsStream = arweave.getAllSnapshotsOfDrive(
      driveId,
      lastBlockHeight,
      ownerAddress: ownerAddress,
    );

    snapshotItems = await SnapshotItem.instantiateAll(
      snapshotsStream,
      arweave: arweave,
    ).toList();
  }

  final SnapshotDriveHistory snapshotDriveHistory = SnapshotDriveHistory(
    items: snapshotItems,
  );

  final totalRangeToQueryFor = HeightRange(
    rangeSegments: [
      Range(
        start: lastBlockHeight,
        end: currentBlockHeight,
      ),
    ],
  );

  final HeightRange gqlDriveHistorySubRanges = HeightRange.difference(
    totalRangeToQueryFor,
    snapshotDriveHistory.subRanges,
  );

  final GQLDriveHistory gqlDriveHistory = GQLDriveHistory(
    subRanges: gqlDriveHistorySubRanges,
    arweave: arweave,
    driveId: driveId,
    ownerAddress: ownerAddress,
  );

  logger.d('Total range to query for: ${totalRangeToQueryFor.rangeSegments}\n'
      'Sub ranges in snapshots (DRIVE ID: $driveId): ${snapshotDriveHistory.subRanges.rangeSegments}\n'
      'Sub ranges in GQL (DRIVE ID: $driveId): ${gqlDriveHistorySubRanges.rangeSegments}');

  final DriveHistoryComposite driveHistory = DriveHistoryComposite(
    subRanges: totalRangeToQueryFor,
    gqlDriveHistory: gqlDriveHistory,
    snapshotDriveHistory: snapshotDriveHistory,
  );

  final transactionsStream = driveHistory.getNextStream();

  /// The first block height of this drive.
  int? firstBlockHeight;

  /// In order to measure the sync progress by the block height, we use the difference
  /// between the first block and the `currentBlockHeight`
  late int totalBlockHeightDifference;

  /// This percentage is based on block heights.
  var fetchPhasePercentage = 0.0;

  /// First phase of the sync
  /// Here we get all transactions from its drive.
  await for (DriveHistoryTransaction t in transactionsStream) {
    double calculatePercentageBasedOnBlockHeights() {
      final block = t.block;

      if (block != null) {
        return (1 -
            ((currentBlockHeight - block.height) / totalBlockHeightDifference));
      }
      logger.d(
        'The transaction block is null. Transaction node id: ${t.id}',
      );

      logger.d('New fetch-phase percentage: $fetchPhasePercentage');

      /// if the block is null, we don't calculate and keep the same percentage
      return fetchPhasePercentage;
    }

    /// Initialize only once `firstBlockHeight` and `totalBlockHeightDifference`
    if (firstBlockHeight == null) {
      final block = t.block;

      if (block != null) {
        firstBlockHeight = block.height;
        totalBlockHeightDifference = currentBlockHeight - firstBlockHeight;
        logger.d(
          'First height: $firstBlockHeight, totalHeightDiff: $totalBlockHeightDifference',
        );
      } else {
        logger.d(
          'The transaction block is null. Transaction node id: ${t.id}',
        );
      }
    }

    logger.d('Adding transaction ${t.id}');
    transactions.add(t);

    /// We can only calculate the fetch percentage if we have the `firstBlockHeight`
    if (firstBlockHeight != null) {
      if (totalBlockHeightDifference > 0) {
        fetchPhasePercentage = calculatePercentageBasedOnBlockHeights();
      } else {
        // If the difference is zero means that the first phase was concluded.
        logger.d('The first phase just finished!');
        fetchPhasePercentage = 1;
      }
      final percentage =
          calculatePercentageBasedOnBlockHeights() * fetchPhaseWeight;
      yield percentage;
    }
  }

  logger.d('Done fetching data - ${gqlDriveHistory.driveId}');

  promptToSnapshotBloc.add(
    CountSyncedTxs(
      driveId: driveId,
      txsSyncedWithGqlCount: gqlDriveHistory.txCount,
      wasDeepSync: lastBlockHeight == 0,
    ),
  );

  final fetchPhaseTotalTime =
      DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

  logger.d(
      'Duration of fetch phase for ${drive.name}: $fetchPhaseTotalTime ms. Progress by block height: $fetchPhasePercentage%. Starting parse phase');

  try {
    yield* _parseDriveTransactionsIntoDatabaseEntities(
      ghostFolders: ghostFolders,
      driveDao: driveDao,
      arweave: arweave,
      database: database,
      transactions: transactions,
      drive: drive,
      driveKey: driveKey,
      currentBlockHeight: currentBlockHeight,
      lastBlockHeight: lastBlockHeight,
      batchSize: transactionParseBatchSize,
      snapshotDriveHistory: snapshotDriveHistory,
      ownerAddress: ownerAddress,
    ).map(
      (parseProgress) => parseProgress * 0.9,
    );
  } catch (e) {
    logger.e('[Sync Drive] Error while parsing transactions', e);
    rethrow;
  }

  await SnapshotItemOnChain.dispose(drive.id);

  final syncDriveTotalTime =
      DateTime.now().difference(startSyncDT).inMilliseconds;

  final averageBetweenFetchAndGet = fetchPhaseTotalTime / syncDriveTotalTime;

  logger.i(
      'Drive ${drive.name} completed parse phase. Progress by block height: $fetchPhasePercentage%. Starting parse phase. Sync duration: $syncDriveTotalTime ms. Parsing used ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of drive sync process');
}

Future<void> _updateLicenses({
  required DriveDao driveDao,
  required ArweaveService arweave,
  required LicenseService licenseService,
  required List<FileRevision> revisionsToSyncLicense,
}) async {
  final licenseAssertionTxIds = revisionsToSyncLicense
      .where((rev) => rev.licenseTxId != rev.dataTxId)
      .map((e) => e.licenseTxId!)
      .toList();

  logger.d('Syncing ${licenseAssertionTxIds.length} license assertions');

  await for (final licenseAssertionTxsBatch
      in arweave.getLicenseAssertions(licenseAssertionTxIds)) {
    final licenseAssertionEntities = licenseAssertionTxsBatch
        .map((tx) => LicenseAssertionEntity.fromTransaction(tx));
    final licenseCompanions = licenseAssertionEntities.map((entity) {
      final revision = revisionsToSyncLicense.firstWhere(
        (rev) => rev.licenseTxId == entity.txId,
      );
      final licenseType =
          licenseService.licenseTypeByTxId(entity.licenseDefinitionTxId);
      return entity.toCompanion(
        fileId: revision.fileId,
        driveId: revision.driveId,
        licenseType: licenseType ?? LicenseType.unknown,
      );
    });

    logger
        .d('Inserting batch of ${licenseCompanions.length} license assertions');

    await driveDao.transaction(
      () async => {
        for (final licenseAssertionCompanion in licenseCompanions)
          {await driveDao.insertLicense(licenseAssertionCompanion)}
      },
    );
  }

  final licenseComposedTxIds = revisionsToSyncLicense
      .where((rev) => rev.licenseTxId == rev.dataTxId)
      .map((e) => e.licenseTxId!)
      .toList();

  logger.d('Syncing ${licenseComposedTxIds.length} composed licenses');

  await for (final licenseComposedTxsBatch
      in arweave.getLicenseComposed(licenseComposedTxIds)) {
    final licenseComposedEntities = licenseComposedTxsBatch
        .map((tx) => LicenseComposedEntity.fromTransaction(tx));
    final licenseCompanions = licenseComposedEntities.map((entity) {
      final revision = revisionsToSyncLicense.firstWhere(
        (rev) => rev.licenseTxId == entity.txId,
      );
      final licenseType =
          licenseService.licenseTypeByTxId(entity.licenseDefinitionTxId);
      return entity.toCompanion(
        fileId: revision.fileId,
        driveId: revision.driveId,
        licenseType: licenseType ?? LicenseType.unknown,
      );
    });

    logger
        .d('Inserting batch of ${licenseCompanions.length} composed licenses');

    await driveDao.transaction(
      () async => {
        for (final licenseAssertionCompanion in licenseCompanions)
          {await driveDao.insertLicense(licenseAssertionCompanion)}
      },
    );
  }
}

Future<void> _updateTransactionStatuses({
  required DriveDao driveDao,
  required ArweaveService arweave,
  List<TxID> txsIdsToSkip = const [],
}) async {
  final pendingTxMap = {
    for (final tx in await driveDao.pendingTransactions().get()) tx.id: tx,
  };

  /// Remove all confirmed transactions from the pending map
  /// and update the status of the remaining ones

  logger.i(
    'Skipping status update for ${txsIdsToSkip.length} transactions that were captured in snapshots',
  );

  for (final txId in txsIdsToSkip) {
    pendingTxMap.remove(txId);
  }

  final length = pendingTxMap.length;
  final list = pendingTxMap.keys.toList();

  // Thats was discovered by tests at profile mode.
  // TODO(@thiagocarvalhodev): Revisit
  const page = 5000;

  for (var i = 0; i < length / page; i++) {
    final confirmations = <String?, int>{};
    final currentPage = <String>[];

    /// Mounts the list to be iterated
    for (var j = i * page; j < ((i + 1) * page); j++) {
      if (j >= length) {
        break;
      }
      currentPage.add(list[j]);
    }

    final map = await arweave.getTransactionConfirmations(currentPage.toList());

    map.forEach((key, value) {
      confirmations.putIfAbsent(key, () => value);
    });

    await driveDao.transaction(() async {
      for (final txId in currentPage) {
        final txConfirmed =
            confirmations[txId]! >= kRequiredTxConfirmationCount;
        final txNotFound = confirmations[txId]! < 0;

        String? txStatus;

        DateTime? transactionDateCreated;

        if (pendingTxMap[txId]!.transactionDateCreated != null) {
          transactionDateCreated = pendingTxMap[txId]!.transactionDateCreated!;
        } else {
          transactionDateCreated = await _getDateCreatedByDataTx(
            driveDao: driveDao,
            dataTx: txId,
          );
        }

        if (txConfirmed) {
          txStatus = TransactionStatus.confirmed;
        } else if (txNotFound) {
          // Only mark transactions as failed if they are unconfirmed for over 45 minutes
          // as the transaction might not be queryable for right after it was created.
          final abovePendingThreshold = DateTime.now()
                  .difference(pendingTxMap[txId]!.dateCreated)
                  .inMinutes >
              kRequiredTxConfirmationPendingThreshold;

          // Assume that data tx that weren't mined up to a maximum of
          // `_pendingWaitTime` was failed.
          if (abovePendingThreshold ||
              _isOverThePendingTime(transactionDateCreated)) {
            txStatus = TransactionStatus.failed;
          }
        }
        if (txStatus != null) {
          await driveDao.writeToTransaction(
            NetworkTransactionsCompanion(
              transactionDateCreated: Value(transactionDateCreated),
              id: Value(txId),
              status: Value(txStatus),
            ),
          );
        }
      }
    });

    await Future.delayed(const Duration(milliseconds: 200));
  }
  await driveDao.transaction(() async {
    for (final txId in txsIdsToSkip) {
      await driveDao.writeToTransaction(
        NetworkTransactionsCompanion(
          id: Value(txId),
          status: const Value(TransactionStatus.confirmed),
        ),
      );
    }
  });
}

bool _isOverThePendingTime(DateTime? transactionCreatedDate) {
  // If don't have the date information we cannot assume that is over the pending time
  if (transactionCreatedDate == null) {
    return false;
  }

  return DateTime.now().isAfter(transactionCreatedDate.add(_pendingWaitTime));
}

Future<DateTime?> _getDateCreatedByDataTx({
  required DriveDao driveDao,
  required String dataTx,
}) async {
  final rev = await driveDao.fileRevisionByDataTx(tx: dataTx).get();

  // no file found
  if (rev.isEmpty) {
    return null;
  }

  return rev.first.dateCreated;
}
