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
import 'package:ardrive/utils/html/html_util.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
import 'package:retry/retry.dart';

part 'sync_state.dart';

abstract class LinearProgress {
  double get progress;
}

class SyncProgress extends LinearProgress {
  SyncProgress(
      {required this.entitiesNumber,
      required this.progress,
      required this.entitiesSynced,
      required this.drivesCount,
      required this.drivesSynced,
      required this.numberOfDrivesAtGetMetadataPhase});

  factory SyncProgress.initial() => SyncProgress(
      entitiesNumber: 0,
      progress: 0,
      entitiesSynced: 0,
      drivesCount: 0,
      drivesSynced: 0,
      numberOfDrivesAtGetMetadataPhase: 0);

  factory SyncProgress.emptySyncCompleted() => SyncProgress(
      entitiesNumber: 0,
      progress: 1,
      entitiesSynced: 0,
      drivesCount: 0,
      drivesSynced: 0,
      numberOfDrivesAtGetMetadataPhase: 0);

  final int entitiesNumber;
  final int entitiesSynced;
  @override
  final double progress;
  final int drivesSynced;
  final int drivesCount;
  final int numberOfDrivesAtGetMetadataPhase;

  SyncProgress copyWith(
          {int? entitiesNumber,
          int? entitiesSynced,
          double? progress,
          int? drivesSynced,
          int? drivesCount,
          int? numberOfDrivesAtGetMetadataPhase}) =>
      SyncProgress(
          entitiesNumber: entitiesNumber ?? this.entitiesNumber,
          progress: progress ?? this.progress,
          entitiesSynced: entitiesSynced ?? this.entitiesSynced,
          drivesCount: drivesCount ?? this.drivesCount,
          drivesSynced: drivesSynced ?? this.drivesSynced,
          numberOfDrivesAtGetMetadataPhase: numberOfDrivesAtGetMetadataPhase ??
              this.numberOfDrivesAtGetMetadataPhase);
}

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
    createSyncStream();
    restartSyncOnFocus();
    // Sync ArConnect
    createArConnectSyncStream();
    restartArConnectSyncOnFocus();
  }

  void createSyncStream() {
    _syncSub?.cancel();
    _syncSub = Stream.periodic(const Duration(minutes: kSyncTimerDuration))
        // Do not start another sync until the previous sync has completed.
        .map((value) => Stream.fromFuture(startSync()))
        .listen((_) {});
    startSync();
  }

  void restartSyncOnFocus() {
    whenBrowserTabIsUnhidden(() {
      if (_lastSync != null &&
          DateTime.now().difference(_lastSync!).inMinutes <
              kSyncTimerDuration) {
        return;
      }
      Future.delayed(Duration(seconds: 2)).then((value) => createSyncStream());
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
        Future.delayed(Duration(seconds: 2))
            .then((value) => createArConnectSyncStream());
      });
    }
  }

  final ghostFolders = <FolderID, GhostFolder>{};
  final ghostFoldersByDrive =
      <DriveID, Map<FolderID, FolderEntriesCompanion>>{};

  late double _totalProgress;

  Future<void> startSync() async {
    if (state is SyncInProgress) {
      return;
    }

    _syncProgress = SyncProgress.initial();

    _totalProgress = 0;

    try {
      final profile = _profileCubit.state;
      String? ownerAddress;

      _initSync = DateTime.now();
      print('Syncing...');
      emit(SyncInProgress());
      // Only sync in drives owned by the user if they're logged in.
      if (profile is ProfileLoggedIn) {
        //Check if profile is ArConnect to skip sync while tab is hidden
        ownerAddress = profile.walletAddress;
        final isArConnect = await _profileCubit.isCurrentProfileArConnect();

        if (isArConnect && isBrowserTabHidden()) {
          print('Tab hidden, skipping sync...');
          emit(SyncIdle());
          return;
        }

        if (_activityCubit.state is ActivityInProgress) {
          print('Uninterruptable activity in progress, skipping sync...');
          emit(SyncIdle());
          return;
        }

        // This syncs in the latest info on drives owned by the user and will be overwritten
        // below when the full sync process is ran.
        //
        // It also adds the encryption keys onto the drive models which isn't touched by the
        // later system.
        final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
            profile.wallet, profile.password);

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
          () async => await getCurrentBlockHeight(), onRetry: (exception) {
        print(
          'Retrying for get the current block height on exception ${exception.toString()}',
        );
      });

      _syncProgress = _syncProgress.copyWith(drivesCount: drives.length);

      print('Current block height number $currentBlockHeight');

      final driveSyncProcesses = drives.map((drive) => _syncDrive(
            drive.id,
            lastBlockHeight: calculateSyncLastBlockHeight(
              drive.lastBlockHeight!,
            ),
            currentBlockheight: currentBlockHeight,
          ).handleError((error, stackTrace) {
            print(
                'Error syncing drive with id ${drive.id}. Skipping sync on this drive.\nException: ${onError.toString()}\nStackTrace: ${stackTrace.toString()}');
            addError(error!);
          }));

      await Future.wait(driveSyncProcesses.map((driveSyncProgress) async {
        await for (var syncProgress in driveSyncProgress) {
          syncProgressController.add(syncProgress);
        }
        _syncProgress = _syncProgress.copyWith(
            drivesSynced: _syncProgress.drivesSynced + 1);
        syncProgressController.add(_syncProgress);
      }));

      print(
          'Syncing drives finished.\nDrives quantity: ${_syncProgress.drivesCount}\n'
          'The total progress was ${(_syncProgress.progress * 100).roundToDouble()}');

      await createGhosts(ownerAddress: ownerAddress);

      /// In order to have a smooth transition at the end.
      await Future.delayed(const Duration(milliseconds: 1000));

      await Future.wait([
        if (profile is ProfileLoggedIn) _profileCubit.refreshBalance(),
        _updateTransactionStatuses(),
      ]);
    } catch (err, stackTrace) {
      _printSyncError(err, stackTrace);
      addError(err);
    }
    _lastSync = DateTime.now();

    print('The sync process took: '
        '${_lastSync!.difference(_initSync).inMilliseconds} milliseconds to finish.\n');

    emit(SyncIdle());
  }

  int calculateSyncLastBlockHeight(int lastBlockHeight) {
    if (_lastSync != null) {
      return lastBlockHeight;
    } else {
      return max(lastBlockHeight - kBlockHeightLookBack, 0);
    }
  }

  Future<int> getCurrentBlockHeight() async {
    final currentBlockHeight = await arweave.getCurrentBlockHeight();

    if (currentBlockHeight < 0) {
      throw Exception(
          'The current block height $currentBlockHeight is negative. It should be equal or greater than 0.');
    }
    return currentBlockHeight;
  }

  Future<void> createGhosts({String? ownerAddress}) async {
    //Finalize missing parent list
    for (final ghostFolder in ghostFolders.values) {
      final folderExists = (await _driveDao
              .folderById(
                  driveId: ghostFolder.driveId, folderId: ghostFolder.folderId)
              .getSingleOrNull()) !=
          null;

      if (folderExists) {
        continue;
      }

      // Add to database
      final drive =
          await _driveDao.driveById(driveId: ghostFolder.driveId).getSingle();

      // Dont create ghost folder if the ghost is a missing root folder
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
      );

      await _driveDao.into(_driveDao.folderEntries).insert(folderEntry);
      ghostFoldersByDrive.putIfAbsent(
          drive.id, () => {folderEntry.id: folderEntry.toCompanion(false)});
    }
    await Future.wait([
      ...ghostFoldersByDrive.entries
          .map((entry) => generateFsEntryPaths(entry.key, entry.value, {})),
    ]);
  }

  Stream<SyncProgress> _syncDrive(
    String driveId, {
    required int currentBlockheight,
    required int lastBlockHeight,
  }) async* {
    /// Variables to count the current drive's progress information
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();

    final startSyncDT = DateTime.now();

    print('$startSyncDT: Starting Drive ${drive.name} sync.');

    SecretKey? driveKey;

    if (drive.isPrivate) {
      final profile = _profileCubit.state;

      // Only sync private drives when the user is logged in.
      if (profile is ProfileLoggedIn) {
        driveKey = await _driveDao.getDriveKey(drive.id, profile.cipherKey);
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(drive.id);
        if (driveKey == null) {
          throw StateError('Drive key not found');
        }
      }
    }
    final fetchPhaseStartDT = DateTime.now();

    print(
        '${DateTime.now()} : Getting all information about the drive ${drive.name}\n');

    final transactions =
        <DriveEntityHistory$Query$TransactionConnection$TransactionEdge>[];

    final transactionsStream = _arweave
        .getAllTransactionsFromDrive(driveId, lastBlockHeight: lastBlockHeight)
        .handleError((err) {
      addError(err);
    }).asBroadcastStream();

    /// The first block height from this drive.
    int? firstBlockHeight;

    /// In order to measure the sync progress by the block height, we use the difference
    /// between the first block and the `currentBlockheight`
    int? totalBlockHeightDifference;

    /// This percentage is based on block heights.
    var fetchPhasePercentage = 0.0;

    /// First phase of the sync
    /// Here we get all transactions from its drive.
    await for (var t in transactionsStream) {
      late int currentPageBlockHeight;

      if (t.isEmpty) continue;

      double _calculatePercentageBasedOnBlockHeights() => (1 -
          ((currentBlockheight - t.last.node.block!.height) /
              totalBlockHeightDifference!));

      if (firstBlockHeight == null) {
        firstBlockHeight = t.first.node.block!.height;
        totalBlockHeightDifference = currentBlockheight - firstBlockHeight;
        print('firstBlockHeight $firstBlockHeight\n'
            'totalBlockHeightDifference $totalBlockHeightDifference\n'
            'lastBlockHeight $lastBlockHeight\n');
      }

      currentPageBlockHeight = t.last.node.block!.height;

      transactions.addAll(t);

      print('firstBlockHeight $firstBlockHeight\n'
          'currentBlockheight $currentBlockheight\n'
          'totalBlockHeightDifference $totalBlockHeightDifference\n'
          'currentPageBlockHeight $currentPageBlockHeight\n'
          'percentage based on block height: ${(1 - ((currentBlockheight - currentPageBlockHeight) / totalBlockHeightDifference!)) * 100}');

      _totalProgress += _calculateProgressInFetchPhasePercentage(
          _calculatePercentageProgress(
              fetchPhasePercentage, _calculatePercentageBasedOnBlockHeights()));

      _syncProgress = _syncProgress.copyWith(
          progress: _totalProgress,
          entitiesNumber: _syncProgress.entitiesNumber + t.length);

      yield _syncProgress;

      if (totalBlockHeightDifference > 0) {
        fetchPhasePercentage += _calculatePercentageProgress(
            fetchPhasePercentage, _calculatePercentageBasedOnBlockHeights());
      } else {
        // If the difference is zero means that the first phase was concluded.
        fetchPhasePercentage = 1;
      }
    }

    final fetchPhaseTotalTime =
        DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

    print(
        'It tooks $fetchPhaseTotalTime milliseconds to get all ${drive.name}\'s transactions.\n');

    print('FetchPhasePercentage: $fetchPhasePercentage\n');

    /// Fill the remaining percentage.
    /// It is needed because the phase one isn't accurate and possibly will not
    /// match 100% everytime
    _totalProgress +=
        _calculateProgressInFetchPhasePercentage((1 - fetchPhasePercentage));
    print('Total progress after fetch phase: $_totalProgress');
    _syncProgress = _syncProgress.copyWith(progress: _totalProgress);

    yield _syncProgress;

    print('Drive ${drive.name} is going to the 2nd phase\n');

    _syncProgress = _syncProgress.copyWith(
        numberOfDrivesAtGetMetadataPhase:
            _syncProgress.numberOfDrivesAtGetMetadataPhase + 1);

    yield* _syncSecondPhase(
        transactions: transactions,
        drive: drive,
        driveKey: driveKey,
        currentBlockHeight: currentBlockheight,
        lastBlockHeight: lastBlockHeight);

    print('Drive ${drive.name} passed the 2nd phase\n');

    final syncDriveTotalTime =
        DateTime.now().difference(startSyncDT).inMilliseconds;

    print(
        'It tooks $syncDriveTotalTime in milleseconds to sync the ${drive.name}.\n');

    final averageBetweenFetchAndGet = fetchPhaseTotalTime / syncDriveTotalTime;

    print(
        'The fetch phase took: ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of the entire drive process.\n');

    _syncProgress = _syncProgress.copyWith(
        numberOfDrivesAtGetMetadataPhase:
            _syncProgress.numberOfDrivesAtGetMetadataPhase - 1);
  }

  /// Sync Second Phase
  ///
  /// Paginate the process in pages of `pageCount`
  ///
  /// It is needed because of close connection issues when made a huge number of requests to get the metadata,
  /// and also to accomplish a better visualization of the sync progress.
  Stream<SyncProgress> _syncSecondPhase(
      {required List<
              DriveEntityHistory$Query$TransactionConnection$TransactionEdge>
          transactions,
      required Drive drive,
      required SecretKey? driveKey,
      required int lastBlockHeight,
      required int currentBlockHeight}) async* {
    final pageCount =
        200 ~/ (_syncProgress.drivesCount - _syncProgress.drivesSynced);
    var currentDriveEntitiesSynced = 0;
    var driveSyncProgress = 0.0;

    print(
        'number of drives at 2 phase : ${_syncProgress.numberOfDrivesAtGetMetadataPhase}');

    print('Transactions list length: ${transactions.length}');

    if (transactions.isEmpty) {
      await _driveDao.writeToDrive(DrivesCompanion(
        id: Value(drive.id),
        lastBlockHeight: Value(currentBlockHeight),
        syncCursor: Value(null),
      ));

      /// If there's nothing to sync, we assume that all were synced
      _totalProgress += _calculateProgressInGetPhasePercentage(1); // 100%
      _syncProgress = _syncProgress.copyWith(progress: _totalProgress);
      yield _syncProgress;
      return;
    }
    final currentDriveEntitiesCounter = transactions.length;

    print(
        'The total number of entities of the drive ${drive.name} to be synced is: $currentDriveEntitiesCounter\n');

    final owner = await arweave.getOwnerForDriveEntityWithId(drive.id);

    double _calculateDriveSyncPercentage() =>
        currentDriveEntitiesSynced / currentDriveEntitiesCounter;

    double _calculateDrivePercentProgress() => _calculatePercentageProgress(
        driveSyncProgress, _calculateDriveSyncPercentage());

    yield* _paginateProcess<
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge>(
        list: transactions,
        pageCount: pageCount,
        itemsPerPageCallback: (items) async* {
          print('${DateTime.now()} Getting metadata from drive ${drive.name}');

          final entityHistory =
              await _arweave.createDriveEntityHistoryFromTransactions(
                  items, driveKey, owner, lastBlockHeight);

          // Create entries for all the new revisions of file and folders in this drive.
          final newEntities = entityHistory.blockHistory
              .map((b) => b.entities)
              .expand((entities) => entities);

          currentDriveEntitiesSynced += items.length - newEntities.length;

          _totalProgress += _calculateProgressInGetPhasePercentage(
              _calculateDrivePercentProgress());

          _syncProgress = _syncProgress.copyWith(
              progress: _totalProgress,
              entitiesSynced:
                  _syncProgress.entitiesSynced + currentDriveEntitiesSynced);

          yield _syncProgress;

          driveSyncProgress += _calculatePercentageProgress(
              driveSyncProgress, _calculateDriveSyncPercentage());

          // Handle the last page of newEntities, i.e; There's nothing more to sync
          if (newEntities.length < pageCount) {
            // Reset the sync cursor after every sync to pick up files from other instances of the app.
            // (Different tab, different window, mobile, desktop etc)
            await _driveDao.writeToDrive(DrivesCompanion(
              id: Value(drive.id),
              lastBlockHeight: Value(currentBlockHeight),
              syncCursor: Value(null),
            ));
          }

          await _db.transaction(() async {
            final latestDriveRevision = await _addNewDriveEntityRevisions(
                newEntities.whereType<DriveEntity>());
            final latestFolderRevisions = await _addNewFolderEntityRevisions(
                drive.id, newEntities.whereType<FolderEntity>());
            final latestFileRevisions = await _addNewFileEntityRevisions(
                drive.id, newEntities.whereType<FileEntity>());

            // Check and handle cases where there's no more revisions
            final updatedDrive = latestDriveRevision != null
                ? await _computeRefreshedDriveFromRevision(latestDriveRevision)
                : null;

            final updatedFoldersById =
                await _computeRefreshedFolderEntriesFromRevisions(
                    drive.id, latestFolderRevisions);
            final updatedFilesById =
                await _computeRefreshedFileEntriesFromRevisions(
                    drive.id, latestFileRevisions);

            currentDriveEntitiesSynced += newEntities.length;

            currentDriveEntitiesSynced -=
                updatedFoldersById.length + updatedFilesById.length;

            _totalProgress += _calculateProgressInGetPhasePercentage(
                _calculateDrivePercentProgress());

            _syncProgress = _syncProgress.copyWith(
                progress: _totalProgress,
                entitiesSynced:
                    _syncProgress.entitiesSynced + currentDriveEntitiesSynced);

            driveSyncProgress += _calculatePercentageProgress(
                driveSyncProgress, _calculateDriveSyncPercentage());

            // Update the drive model, making sure to not overwrite the existing keys defined on the drive.
            if (updatedDrive != null) {
              await (_db.update(_db.drives)..whereSamePrimaryKey(updatedDrive))
                  .write(updatedDrive);
            }

            // Update the folder and file entries before generating their new paths.
            await _db.batch((b) {
              b.insertAllOnConflictUpdate(
                  _db.folderEntries, updatedFoldersById.values.toList());
              b.insertAllOnConflictUpdate(
                  _db.fileEntries, updatedFilesById.values.toList());
            });

            await generateFsEntryPaths(
                drive.id, updatedFoldersById, updatedFilesById);

            currentDriveEntitiesSynced +=
                updatedFoldersById.length + updatedFilesById.length;

            _totalProgress += _calculateProgressInGetPhasePercentage(
                _calculateDrivePercentProgress());

            _syncProgress = _syncProgress.copyWith(
                progress: _totalProgress,
                entitiesSynced:
                    _syncProgress.entitiesSynced + currentDriveEntitiesSynced);

            driveSyncProgress += _calculatePercentageProgress(
                driveSyncProgress, _calculateDriveSyncPercentage());
          });

          yield _syncProgress;
        });
    print('''
        ${'- - ' * 10}
        Drive: ${drive.name} sync finishes.\n
        The progress was:                     ${driveSyncProgress * 100}
        Total progress until now:             ${(_totalProgress * 100).roundToDouble()}
        The number of entities to be synced:  $currentDriveEntitiesCounter
        The Total number of synced entities:  $currentDriveEntitiesSynced
        ''');
  }

  /// Divided by 2 because we have 2 phases
  double _calculateProgressInGetPhasePercentage(double currentDriveProgress) =>
      (currentDriveProgress / _syncProgress.drivesCount) * 0.9; // 90%

  double _calculateProgressInFetchPhasePercentage(
          double currentDriveProgress) =>
      (currentDriveProgress / _syncProgress.drivesCount) * 0.1; // 10%

  double _calculatePercentageProgress(
          double currentPercentage, double newPercentage) =>
      newPercentage - currentPercentage;

  Stream<SyncProgress> _paginateProcess<T>(
      {required List<T> list,
      required Stream<SyncProgress> Function(List<T> items)
          itemsPerPageCallback,
      required int pageCount}) async* {
    if (list.isEmpty) {
      return;
    }

    final length = list.length;

    for (var i = 0; i < length / pageCount; i++) {
      final currentPage = <T>[];

      /// Mounts the list to be iterated
      for (var j = i * pageCount; j < ((i + 1) * pageCount); j++) {
        if (j >= length) {
          break;
        }

        currentPage.add(list[j]);
      }

      yield* itemsPerPageCallback(currentPage);
    }
  }

  /// Computes the new drive revisions from the provided entities, inserts them into the database,
  /// and returns the latest revision.
  Future<DriveRevisionsCompanion?> _addNewDriveEntityRevisions(
    Iterable<DriveEntity> newEntities,
  ) async {
    DriveRevisionsCompanion? latestRevision;

    final newRevisions = <DriveRevisionsCompanion>[];
    for (final entity in newEntities) {
      latestRevision ??= await _driveDao
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

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.driveRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .map(
                (rev) => NetworkTransactionsCompanion.insert(
                  transactionDateCreated: rev.dateCreated,
                  id: rev.metadataTxId.value,
                  status: Value(TransactionStatus.confirmed),
                ),
              )
              .toList());
    });

    return latestRevision;
  }

  /// Computes the new folder revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions(
      String driveId, Iterable<FolderEntity> newEntities) async {
    // The latest folder revisions, keyed by their entity ids.
    final latestRevisions = <String, FolderRevisionsCompanion>{};

    final newRevisions = <FolderRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        final revisions = (await _driveDao
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

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.folderRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
          newRevisions
              .map(
                (rev) => NetworkTransactionsCompanion.insert(
                  transactionDateCreated: rev.dateCreated,
                  id: rev.metadataTxId.value,
                  status: Value(TransactionStatus.confirmed),
                ),
              )
              .toList());
    });

    return latestRevisions.values.toList();
  }

  /// Computes the new file revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions(
      String driveId, Iterable<FileEntity> newEntities) async {
    // The latest file revisions, keyed by their entity ids.
    final latestRevisions = <String, FileRevisionsCompanion>{};

    final newRevisions = <FileRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id) &&
          entity.parentFolderId != null) {
        final revisions = await _driveDao
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
      // If Parent-Folder-Id is missing for a file, put it in the rootfolder

      entity.parentFolderId = entity.parentFolderId ?? rootPath;
      final revision =
          entity.toRevisionCompanion(performedAction: revisionPerformedAction);

      if (revision.action.value.isEmpty) {
        continue;
      }

      newRevisions.add(revision);
      latestRevisions[entity.id!] = revision;
    }

    await _db.batch((b) {
      b.insertAllOnConflictUpdate(_db.fileRevisions, newRevisions);
      b.insertAllOnConflictUpdate(
          _db.networkTransactions,
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

  /// Computes the refreshed drive entries from the provided revisions and returns them as a map keyed by their ids.
  Future<DrivesCompanion> _computeRefreshedDriveFromRevision(
      DriveRevisionsCompanion latestRevision) async {
    final oldestRevision = await _driveDao
        .oldestDriveRevisionByDriveId(driveId: latestRevision.driveId.value)
        .getSingleOrNull();

    return latestRevision.toEntryCompanion().copyWith(
        dateCreated: Value(oldestRevision?.dateCreated ??
            latestRevision.dateCreated as DateTime));
  }

  /// Computes the refreshed folder entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FolderEntriesCompanion>>
      _computeRefreshedFolderEntriesFromRevisions(String driveId,
          List<FolderRevisionsCompanion> revisionsByFolderId) async {
    final updatedFoldersById = {
      for (final revision in revisionsByFolderId)
        revision.folderId.value: revision.toEntryCompanion(),
    };

    for (final folderId in updatedFoldersById.keys) {
      final oldestRevision = await _driveDao
          .oldestFolderRevisionByFolderId(driveId: driveId, folderId: folderId)
          .getSingleOrNull();

      updatedFoldersById[folderId] = updatedFoldersById[folderId]!.copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFoldersById[folderId]!.dateCreated as DateTime));
    }

    return updatedFoldersById;
  }

  /// Computes the refreshed file entries from the provided revisions and returns them as a map keyed by their ids.
  Future<Map<String, FileEntriesCompanion>>
      _computeRefreshedFileEntriesFromRevisions(String driveId,
          List<FileRevisionsCompanion> revisionsByFileId) async {
    final updatedFilesById = {
      for (final revision in revisionsByFileId)
        revision.fileId.value: revision.toEntryCompanion(),
    };

    for (final fileId in updatedFilesById.keys) {
      final oldestRevision = await _driveDao
          .oldestFileRevisionByFileId(driveId: driveId, fileId: fileId)
          .getSingleOrNull();

      updatedFilesById[fileId] = updatedFilesById[fileId]!.copyWith(
          dateCreated: Value(oldestRevision?.dateCreated ??
              updatedFilesById[fileId]!.dateCreated as DateTime));
    }

    return updatedFilesById;
  }

  /// Generates paths for the folders (and their subchildren) and files provided.
  Future<void> generateFsEntryPaths(
    String driveId,
    Map<String, FolderEntriesCompanion> foldersByIdMap,
    Map<String, FileEntriesCompanion> filesByIdMap,
  ) async {
    final staleFolderTree = <FolderNode>[];
    for (final folder in foldersByIdMap.values) {
      // Get trees of the updated folders and files for path generation.
      final tree = await _driveDao.getFolderTree(driveId, folder.id.value);

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
          ? parentPath + '/' + node.folder.name
          : rootPath;

      await _driveDao
          .updateFolderById(driveId, folderId)
          .write(FolderEntriesCompanion(path: Value(folderPath)));

      for (final staleFileId in node.files.keys) {
        final filePath = folderPath + '/' + node.files[staleFileId]!.name;

        await _driveDao
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
        parentPath = (await _driveDao
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
        final parentPath = await _driveDao
            .folderById(
                driveId: driveId,
                folderId: staleOrphanFile.parentFolderId.value)
            .map((f) => f.path)
            .getSingleOrNull();

        if (parentPath != null) {
          final filePath = parentPath + '/' + staleOrphanFile.name.value;

          await _driveDao.writeToFile(FileEntriesCompanion(
              id: staleOrphanFile.id,
              driveId: staleOrphanFile.driveId,
              path: Value(filePath)));
        } else {
          await addMissingFolder(
            staleOrphanFile.parentFolderId.value,
          );
        }
      }
    }
  }

  Future<void> _updateTransactionStatuses() async {
    final pendingTxMap = {
      for (final tx in await _driveDao.pendingTransactions().get()) tx.id: tx,
    };

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

      final map =
          await _arweave.getTransactionConfirmations(currentPage.toList());

      map.forEach((key, value) {
        confirmations.putIfAbsent(key, () => value);
      });

      await _driveDao.transaction(() async {
        for (final txId in currentPage) {
          final txConfirmed =
              confirmations[txId]! >= kRequiredTxConfirmationCount;
          final txNotFound = confirmations[txId]! < 0;

          var txStatus;

          DateTime? transactionDateCreated;

          if (pendingTxMap[txId]!.transactionDateCreated != null) {
            transactionDateCreated =
                pendingTxMap[txId]!.transactionDateCreated!;
          } else {
            transactionDateCreated = await _getDateCreatedByDataTx(txId);
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
            await _driveDao.writeToTransaction(
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
  }

  bool _isOverThePendingTime(DateTime? transactionCreatedDate) {
    // If don't have the date information we cannot assume that is over the pending time
    if (transactionCreatedDate == null) {
      return false;
    }

    return DateTime.now().isAfter(transactionCreatedDate.add(_pendingWaitTime));
  }

  Future<DateTime?> _getDateCreatedByDataTx(String dataTx) async {
    final rev = await _driveDao.fileRevisionByDataTx(tx: dataTx).get();

    // no file found
    if (rev.isEmpty) {
      return null;
    }

    return rev.first.dateCreated;
  }

  @override
  void onError(Object error, StackTrace stackTrace) {
    _printSyncError(error, stackTrace);
    print('Emiting SyncFailure state');
    emit(SyncFailure(error: error, stackTrace: stackTrace));

    print('Emiting SyncIdle state');
    emit(SyncIdle());
    super.onError(error, stackTrace);
  }

  void _printSyncError(Object error, StackTrace stackTrace) {
    print(
        'An error occurs while sync.\nError: ${error.toString()}\nStacktrace${stackTrace.toString()}');
  }

  @override
  Future<void> close() {
    _syncSub?.cancel();
    return super.close();
  }
}
