import 'dart:async';
import 'dart:math';

import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/entities/license_assertion.dart';
import 'package:ardrive/entities/license_composed.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/drive.dart';
import 'package:ardrive/models/drive_revision.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/models/file_revision.dart';
import 'package:ardrive/models/folder_revision.dart';
import 'package:ardrive/models/license.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/license/license_service.dart';
import 'package:ardrive/services/license/license_state.dart';
import 'package:ardrive/sync/constants.dart';
import 'package:ardrive/sync/domain/ghost_folder.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/sync/utils/network_transaction_utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/drive_history_composite.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:retry/retry.dart';

abstract class SyncRepository {
  Stream<double> syncDriveById({
    required String driveId,
    required String ownerAddress,

    /// This was required because the usage of the `PromptToSnapshotBloc` in the
    /// `SyncCubit` and the `PromptToSnapshotBloc` is not available in the `SyncRepository`
    ///
    /// This functionality should be refactored. The count of synced tx must be done
    /// at the `SyncRepository` level, not at the `PromptToSnapshotBloc` level.
    Function(String driveId, int txCount)? txFechedCallback,
  });

  Stream<SyncProgress> syncAllDrives({
    bool syncDeep = false,
    Wallet? wallet,
    String? password,
    SecretKey? cipherKey,

    /// This was required because the usage of the `PromptToSnapshotBloc` in the
    /// `SyncCubit` and the `PromptToSnapshotBloc` is not available in the `SyncRepository`
    ///
    /// This functionality should be refactored. The count of synced tx must be done
    /// at the `SyncRepository` level, not at the `PromptToSnapshotBloc` level.
    Function(String driveId, int txCount)? txFechedCallback,
  });

  Future<void> updateUserDrives({
    required Wallet wallet,
    required String password,
    required SecretKey cipherKey,
  });

  Future<void> createGhosts({
    required DriveDao driveDao,
    required Map<FolderID, GhostFolder> ghostFolders,
    String? ownerAddress,
  });

  Future<int> getCurrentBlockHeight();

  Future<Map<FolderID, GhostFolder>> generateFsEntryPaths({
    required String driveId,
    required Map<String, FolderEntriesCompanion> foldersByIdMap,
    required Map<String, FileEntriesCompanion> filesByIdMap,
    required Map<FolderID, GhostFolder> ghostFolders,
  });

  factory SyncRepository({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ConfigService configService,
    required LicenseService licenseService,
    required BatchProcessor batchProcessor,
  }) {
    return _SyncRepository(
      arweave: arweave,
      driveDao: driveDao,
      configService: configService,
      licenseService: licenseService,
      batchProcessor: batchProcessor,
    );
  }
}

class _SyncRepository implements SyncRepository {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ConfigService _configService;
  final LicenseService _licenseService;
  final BatchProcessor _batchProcessor;

  DateTime? _lastSync;

  _SyncRepository({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ConfigService configService,
    required LicenseService licenseService,
    required BatchProcessor batchProcessor,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _configService = configService,
        _licenseService = licenseService,
        _batchProcessor = batchProcessor;

  @override
  Stream<SyncProgress> syncAllDrives({
    bool syncDeep = false,
    Wallet? wallet,
    String? password,
    SecretKey? cipherKey,
    Function(String driveId, int txCount)? txFechedCallback,
  }) async* {
    // Sync the contents of each drive attached in the app.
    final drives = await _driveDao.allDrives().map((d) => d).get();

    if (drives.isEmpty) {
      yield SyncProgress.emptySyncCompleted();
      _lastSync = DateTime.now();
    }

    SyncProgress syncProgress = SyncProgress.initial();

    syncProgress = syncProgress.copyWith(drivesCount: drives.length);

    yield syncProgress;

    final currentBlockHeight = await retry(
      () async => await _arweave.getCurrentBlockHeight(),
      onRetry: (exception) => logger.w(
        'Retrying for get the current block height',
      ),
    );

    final ghostFolders = <FolderID, GhostFolder>{};

    final driveSyncProcesses = drives.map((drive) async* {
      yield* _syncDrive(
        drive.id,
        cipherKey: cipherKey,
        ghostFolders: ghostFolders,
        lastBlockHeight: syncDeep
            ? 0
            : _calculateSyncLastBlockHeight(drive.lastBlockHeight!),
        currentBlockHeight: currentBlockHeight,
        transactionParseBatchSize:
            200 ~/ (syncProgress.drivesCount - syncProgress.drivesSynced),
        ownerAddress: drive.ownerAddress,
        txFechedCallback: txFechedCallback,
      );
    });

    double totalProgress = 0;

    final StreamController<SyncProgress> syncProgressController =
        StreamController<SyncProgress>.broadcast();

    Future.wait(
      driveSyncProcesses.map(
        (driveSyncProgress) async {
          double currentDriveProgress = 0;
          await for (var driveProgress in driveSyncProgress) {
            currentDriveProgress =
                (totalProgress + driveProgress) / drives.length;
            if (currentDriveProgress > syncProgress.progress) {
              syncProgress = syncProgress.copyWith(
                progress: currentDriveProgress,
              );
            }
            syncProgressController.add(syncProgress);
          }
          totalProgress += 1;
          syncProgress = syncProgress.copyWith(
            drivesSynced: syncProgress.drivesSynced + 1,
            progress: totalProgress / drives.length,
          );
          syncProgressController.add(syncProgress);
        },
      ),
    ).then((value) async {
      logger.i('Creating ghosts...');

      await createGhosts(
        driveDao: _driveDao,
        ownerAddress: await wallet?.getAddress(),
        ghostFolders: ghostFolders,
      );

      /// Clear the ghost folders after they are created
      ghostFolders.clear();

      logger.i('Ghosts created...');

      logger.i('Syncing licenses...');

      final licenseTxIds = <String>{};
      final revisionsToSyncLicense = (await _driveDao
          .allFileRevisionsWithLicenseReferencedButNotSynced()
          .get())
        ..retainWhere((rev) => licenseTxIds.add(rev.licenseTxId!));
      logger.d('Found ${revisionsToSyncLicense.length} licenses to sync');

      await _updateLicenses(
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
          _updateTransactionStatuses(
            driveDao: _driveDao,
            arweave: _arweave,
            txsIdsToSkip: confirmedFileTxIds,
          ),
        ],
      );

      _lastSync = DateTime.now();
      syncProgressController.close();
    });

    yield* syncProgressController.stream;
  }

  @override
  Stream<double> syncDriveById({
    required String driveId,
    required String ownerAddress,
    Function(String driveId, int txCount)? txFechedCallback,
  }) {
    _lastSync = DateTime.now();
    return _syncDrive(
      driveId,
      ownerAddress: ownerAddress,
      lastBlockHeight: 0,
      currentBlockHeight: 0,
      transactionParseBatchSize: 200,
      txFechedCallback: txFechedCallback,
      ghostFolders: {}, // No ghost folders to start with
    );
  }

  @override
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
        ...ghostFoldersByDrive.entries.map(
          (entry) => _generateFsEntryPaths(
            driveDao: driveDao,
            driveId: entry.key,
            foldersByIdMap: entry.value,
            ghostFolders: ghostFolders,
            filesByIdMap: {},
          ),
        ),
      ],
    );
  }

  @override
  Future<void> updateUserDrives({
    required Wallet wallet,
    required String password,
    required SecretKey cipherKey,
  }) async {
    // This syncs in the latest info on drives owned by the user and will be overwritten
    // below when the full sync process is ran.
    //
    // It also adds the encryption keys onto the drive models which isn't touched by the
    // later system.
    final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
      wallet,
      password,
    );

    await _driveDao.updateUserDrives(userDriveEntities, cipherKey);
  }

  @override
  Future<int> getCurrentBlockHeight() {
    return retry(
      () async => await _arweave.getCurrentBlockHeight(),
      onRetry: (exception) => logger.w(
        'Retrying for get the current block height',
      ),
    );
  }

  @override
  Future<Map<FolderID, GhostFolder>> generateFsEntryPaths({
    required String driveId,
    required Map<String, FolderEntriesCompanion> foldersByIdMap,
    required Map<String, FileEntriesCompanion> filesByIdMap,
    required Map<FolderID, GhostFolder> ghostFolders,
  }) {
    return _generateFsEntryPaths(
      driveDao: _driveDao,
      driveId: driveId,
      foldersByIdMap: foldersByIdMap,
      filesByIdMap: filesByIdMap,
      ghostFolders: ghostFolders,
    );
  }

  int _calculateSyncLastBlockHeight(int lastBlockHeight) {
    logger.d('Calculating sync last block height: $lastBlockHeight');
    if (_lastSync != null) {
      return lastBlockHeight;
    } else {
      return max(lastBlockHeight - kBlockHeightLookBack, 0);
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

      final map =
          await arweave.getTransactionConfirmations(currentPage.toList());

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
            transactionDateCreated =
                pendingTxMap[txId]!.transactionDateCreated!;
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

  Future<List<FileRevision>> _getAllFileEntities({
    required DriveDao driveDao,
  }) async {
    return await driveDao.db.fileRevisions.select().get();
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

  bool _isOverThePendingTime(DateTime? transactionCreatedDate) {
    // If don't have the date information we cannot assume that is over the pending time
    if (transactionCreatedDate == null) {
      return false;
    }

    return DateTime.now().isAfter(transactionCreatedDate.add(pendingWaitTime));
  }

  Stream<double> _syncDrive(
    String driveId, {
    SecretKey? cipherKey,
    required int currentBlockHeight,
    required int lastBlockHeight,
    required int transactionParseBatchSize,
    required Map<FolderID, GhostFolder> ghostFolders,
    required String ownerAddress,
    Function(String driveId, int txCount)? txFechedCallback,
  }) async* {
    /// Variables to count the current drive's progress information
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();
    final startSyncDT = DateTime.now();

    logger.i('Syncing drive: ${drive.id}');

    SecretKey? driveKey;

    if (drive.isPrivate) {
      // Only sync private drives when the user is logged in.
      if (cipherKey != null) {
        driveKey = await _driveDao.getDriveKey(drive.id, cipherKey);
      } else {
        driveKey = await _driveDao.getDriveKeyFromMemory(drive.id);

        if (driveKey == null) {
          throw StateError('Drive key not found');
        }
      }
    }
    final fetchPhaseStartDT = DateTime.now();

    logger.d('Fetching all transactions for drive ${drive.id}');

    final transactions = <DriveHistoryTransaction>[];

    List<SnapshotItem> snapshotItems = [];

    if (_configService.config.enableSyncFromSnapshot) {
      logger.i('Syncing from snapshot: ${drive.id}');

      final snapshotsStream = _arweave.getAllSnapshotsOfDrive(
        driveId,
        lastBlockHeight,
        ownerAddress: ownerAddress,
      );

      snapshotItems = await SnapshotItem.instantiateAll(
        snapshotsStream,
        arweave: _arweave,
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
      arweave: _arweave,
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
              ((currentBlockHeight - block.height) /
                  totalBlockHeightDifference));
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

    txFechedCallback?.call(drive.id, gqlDriveHistory.txCount);

    final fetchPhaseTotalTime =
        DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

    logger.d(
        'Duration of fetch phase for ${drive.name}: $fetchPhaseTotalTime ms. Progress by block height: $fetchPhasePercentage%. Starting parse phase');

    try {
      yield* _parseDriveTransactionsIntoDatabaseEntities(
        ghostFolders: ghostFolders,
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
        'Drive ${drive.name} completed parse phase. Progress by block height: $fetchPhasePercentage%. Starting parse phase. Sync duration: $syncDriveTotalTime ms. Fetching used ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of drive sync process');
  }

  Future<void> _updateLicenses({
    required List<FileRevision> revisionsToSyncLicense,
  }) async {
    final licenseAssertionTxIds = revisionsToSyncLicense
        .where((rev) => rev.licenseTxId != rev.dataTxId)
        .map((e) => e.licenseTxId!)
        .toList();

    logger.d('Syncing ${licenseAssertionTxIds.length} license assertions');

    await for (final licenseAssertionTxsBatch
        in _arweave.getLicenseAssertions(licenseAssertionTxIds)) {
      final licenseAssertionEntities = licenseAssertionTxsBatch
          .map((tx) => LicenseAssertionEntity.fromTransaction(tx));
      final licenseCompanions = licenseAssertionEntities.map((entity) {
        final revision = revisionsToSyncLicense.firstWhere(
          (rev) => rev.licenseTxId == entity.txId,
        );
        final licenseType =
            _licenseService.licenseTypeByTxId(entity.licenseDefinitionTxId);
        return entity.toCompanion(
          fileId: revision.fileId,
          driveId: revision.driveId,
          licenseType: licenseType ?? LicenseType.unknown,
        );
      });

      logger.d(
          'Inserting batch of ${licenseCompanions.length} license assertions');

      await _driveDao.transaction(
        () async => {
          for (final licenseAssertionCompanion in licenseCompanions)
            {await _driveDao.insertLicense(licenseAssertionCompanion)}
        },
      );
    }

    final licenseComposedTxIds = revisionsToSyncLicense
        .where((rev) => rev.licenseTxId == rev.dataTxId)
        .map((e) => e.licenseTxId!)
        .toList();

    logger.d('Syncing ${licenseComposedTxIds.length} composed licenses');

    await for (final licenseComposedTxsBatch
        in _arweave.getLicenseComposed(licenseComposedTxIds)) {
      final licenseComposedEntities = licenseComposedTxsBatch
          .map((tx) => LicenseComposedEntity.fromTransaction(tx));
      final licenseCompanions = licenseComposedEntities.map((entity) {
        final revision = revisionsToSyncLicense.firstWhere(
          (rev) => rev.licenseTxId == entity.txId,
        );
        final licenseType =
            _licenseService.licenseTypeByTxId(entity.licenseDefinitionTxId);
        return entity.toCompanion(
          fileId: revision.fileId,
          driveId: revision.driveId,
          licenseType: licenseType ?? LicenseType.unknown,
        );
      });

      logger.d(
          'Inserting batch of ${licenseCompanions.length} composed licenses');

      await _driveDao.transaction(
        () async => {
          for (final licenseAssertionCompanion in licenseCompanions)
            {await _driveDao.insertLicense(licenseAssertionCompanion)}
        },
      );
    }
  }

  /// Process the transactions from the first phase into database entities.
  /// This is done in batches to improve performance and provide more granular progress
  Stream<double> _parseDriveTransactionsIntoDatabaseEntities({
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
      await _driveDao.writeToDrive(
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

    yield* _batchProcessor.batchProcess<DriveHistoryTransaction>(
        list: transactions,
        batchSize: batchSize,
        endOfBatchCallback: (items) async* {
          final isReadingFromSnapshot = snapshotDriveHistory.items.isNotEmpty;

          if (!isReadingFromSnapshot) {
            logger.d('Getting metadata from drive ${drive.id}');
          }

          final entityHistory =
              await _arweave.createDriveEntityHistoryFromTransactions(
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
            await _driveDao.writeToDrive(DrivesCompanion(
              id: Value(drive.id),
              lastBlockHeight: Value(currentBlockHeight),
              syncCursor: const Value(null),
            ));
          }

          await _driveDao.runTransaction(() async {
            final latestDriveRevision = await _addNewDriveEntityRevisions(
              newEntities: newEntities.whereType<DriveEntity>(),
            );
            final latestFolderRevisions = await _addNewFolderEntityRevisions(
              driveId: drive.id,
              newEntities: newEntities.whereType<FolderEntity>(),
            );
            final latestFileRevisions = await _addNewFileEntityRevisions(
              driveId: drive.id,
              newEntities: newEntities.whereType<FileEntity>(),
            );

            // Check and handle cases where there's no more revisions
            final updatedDrive = latestDriveRevision != null
                ? await _computeRefreshedDriveFromRevision(
                    driveDao: _driveDao,
                    latestRevision: latestDriveRevision,
                  )
                : null;

            final updatedFoldersById =
                await _computeRefreshedFolderEntriesFromRevisions(
              driveDao: _driveDao,
              driveId: drive.id,
              revisionsByFolderId: latestFolderRevisions,
            );
            final updatedFilesById =
                await _computeRefreshedFileEntriesFromRevisions(
              driveDao: _driveDao,
              driveId: drive.id,
              revisionsByFileId: latestFileRevisions,
            );

            numberOfDriveEntitiesParsed += newEntities.length;

            numberOfDriveEntitiesParsed -=
                updatedFoldersById.length + updatedFilesById.length;

            // Update the drive model, making sure to not overwrite the existing keys defined on the drive.
            if (updatedDrive != null) {
              await _driveDao.updateDrive(updatedDrive);
            }

            // Update the folder and file entries before generating their new paths.
            await _driveDao
                .updateFolderEntries(updatedFoldersById.values.toList());
            await _driveDao.updateFileEntries(updatedFilesById.values.toList());

            await _generateFsEntryPaths(
              ghostFolders: ghostFolders,
              driveDao: _driveDao,
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

  /// Computes the new drive revisions from the provided entities, inserts them into the database,
  /// and returns the latest revision.
  Future<DriveRevisionsCompanion?> _addNewDriveEntityRevisions({
    required Iterable<DriveEntity> newEntities,
  }) async {
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

    final newNetworkTransactions = createNetworkTransactionsCompanionsForDrives(
      newRevisions,
    );
    await _driveDao.insertNewDriveRevisions(newRevisions);
    await _driveDao.insertNewNetworkTransactions(newNetworkTransactions);

    return latestRevision;
  }

  /// Computes the new file revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FileRevisionsCompanion>> _addNewFileEntityRevisions({
    required String driveId,
    required Iterable<FileEntity> newEntities,
  }) async {
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
      // If Parent-Folder-Id is missing for a file, put it in the root folder
      try {
        entity.parentFolderId = entity.parentFolderId ?? rootPath;
        final revision = entity.toRevisionCompanion(
            performedAction: revisionPerformedAction);

        if (revision.action.value.isEmpty) {
          continue;
        }

        newRevisions.add(revision);
        latestRevisions[entity.id!] = revision;
      } catch (e, stacktrace) {
        logger.e('Error adding revision for entity', e, stacktrace);
      }
    }
    final newNetworkTransactions = createNetworkTransactionsCompanionsForFiles(
      newRevisions,
    );
    await _driveDao.insertNewFileRevisions(newRevisions);
    await _driveDao.insertNewNetworkTransactions(newNetworkTransactions);

    return latestRevisions.values.toList();
  }

  /// Computes the new folder revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions({
    required String driveId,
    required Iterable<FolderEntity> newEntities,
  }) async {
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
    final newNetworkTransactions =
        createNetworkTransactionsCompanionsForFolders(
      newRevisions,
    );
    await _driveDao.insertNewFolderRevisions(newRevisions);
    await _driveDao.insertNewNetworkTransactions(newNetworkTransactions);

    return latestRevisions.values.toList();
  }
}

const fetchPhaseWeight = 0.1;
const parsePhaseWeight = 0.9;

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
