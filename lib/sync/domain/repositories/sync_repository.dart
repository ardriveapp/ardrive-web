import 'dart:async';
import 'dart:math';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/core/crypto/crypto.dart';
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
import 'package:ardrive/sync/data/snapshot_validation_service.dart';
import 'package:ardrive/sync/domain/ghost_folder.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/sync/domain/sync_cancellation_token.dart';
import 'package:ardrive/sync/domain/sync_failure_simulator.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/sync/utils/network_transaction_utils.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/drive_history_composite.dart';
import 'package:ardrive/utils/snapshots/gql_drive_history.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/snapshot_drive_history.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
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
    SyncCancellationToken? cancellationToken,

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

  Future<int> numberOfFilesInWallet();
  Future<int> numberOfFoldersInWallet();

  factory SyncRepository({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ConfigService configService,
    required LicenseService licenseService,
    required BatchProcessor batchProcessor,
    required SnapshotValidationService snapshotValidationService,
    required ARNSRepository arnsRepository,
    required UserPreferencesRepository userPreferencesRepository,
  }) {
    return _SyncRepository(
      arweave: arweave,
      driveDao: driveDao,
      configService: configService,
      licenseService: licenseService,
      batchProcessor: batchProcessor,
      snapshotValidationService: snapshotValidationService,
      arnsRepository: arnsRepository,
      userPreferencesRepository: userPreferencesRepository,
    );
  }
}

class _SyncRepository implements SyncRepository {
  final ArweaveService _arweave;
  final DriveDao _driveDao;
  final ConfigService _configService;
  final LicenseService _licenseService;
  final BatchProcessor _batchProcessor;
  final SnapshotValidationService _snapshotValidationService;
  final ARNSRepository _arnsRepository;
  final UserPreferencesRepository _userPreferencesRepository;

  final Map<String, GhostFolder> _ghostFolders = {};
  final Set<String> _folderIds = <String>{};

  DateTime? _lastSync;

  _SyncRepository({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ConfigService configService,
    required LicenseService licenseService,
    required BatchProcessor batchProcessor,
    required SnapshotValidationService snapshotValidationService,
    required ARNSRepository arnsRepository,
    required UserPreferencesRepository userPreferencesRepository,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _configService = configService,
        _licenseService = licenseService,
        _snapshotValidationService = snapshotValidationService,
        _batchProcessor = batchProcessor,
        _userPreferencesRepository = userPreferencesRepository,
        _arnsRepository = arnsRepository;

  @override
  Stream<SyncProgress> syncAllDrives({
    bool syncDeep = false,
    Wallet? wallet,
    String? password,
    SecretKey? cipherKey,
    SyncCancellationToken? cancellationToken,
    Function(String driveId, int txCount)? txFechedCallback,
  }) async* {
    final token = cancellationToken ?? SyncCancellationToken();
    if (wallet != null) {
      final address = await wallet.getAddress();

      _arnsRepository
          .getAntRecordsForWallet(address, update: true)
          .catchError((e) {
        logger.e('Error getting ANT records for wallet. Continuing...', e);
        return Future.value(<ANTRecord>[]);
      });
    }

    // Sync the contents of each drive attached in the app.
    final drives = await _driveDao.allDrives().map((d) => d).get();

    if (drives.isEmpty) {
      yield SyncProgress.emptySyncCompleted();
      _lastSync = DateTime.now();
    }

    final numberOfDrivesToSync = drives.length;

    SyncProgress syncProgress =
        SyncProgress.initial().copyWith(drivesCount: numberOfDrivesToSync);

    yield syncProgress;

    final currentBlockHeight = await retry(
      () async => await _arweave.getCurrentBlockHeight(),
      onRetry: (exception) => logger.w(
        'Retrying for get the current block height',
      ),
    );

    double totalProgress = 0;

    final StreamController<SyncProgress> syncProgressController =
        StreamController<SyncProgress>.broadcast();

    // Reset the failure simulator for new sync session
    if (SyncFailureSimulator.instance.isEnabled) {
      SyncFailureSimulator.instance.resetFirstDrive();
    }

    // Track if sync was cancelled
    bool wasCancelled = false;

    // Start the async work but don't wait for it yet
    // Using Future.wait with eagerError: false to continue even if some drives fail
    Future.wait(
      drives.map((drive) async {
        try {
          // Check for cancellation before starting each drive
          token.checkCancellation();

          // Inject simulated failure if enabled (for testing)
          await SyncFailureSimulator.instance.maybeInjectFailure(drive.id);

          final driveSyncProgress = _syncDrive(
            drive.id,
            cipherKey: cipherKey,
            lastBlockHeight: syncDeep
                ? 0
                : _calculateSyncLastBlockHeight(drive.lastBlockHeight!),
            currentBlockHeight: currentBlockHeight,
            transactionParseBatchSize:
                200 ~/ (syncProgress.drivesCount - syncProgress.drivesSynced),
            ownerAddress: drive.ownerAddress,
            txFechedCallback: txFechedCallback,
            cancellationToken: token,
          );

          double currentDriveProgress = 0;
          await for (var driveProgress in driveSyncProgress) {
            // Check for cancellation during sync
            token.checkCancellation();

            // Reserve 10% for post-sync operations (cap drive sync at 90%)
            currentDriveProgress =
                (totalProgress + driveProgress) / numberOfDrivesToSync * 0.9;
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
            // Cap at 90% for drive syncing
            progress: (totalProgress / numberOfDrivesToSync) * 0.9,
          );
          syncProgressController.add(syncProgress);
        } catch (e) {
          // Handle cancellation specially
          if (e is SyncCancelledException) {
            wasCancelled = true;
            // Don't count as failure, just stop processing this drive
            return;
          }

          // Track the failure but continue with other drives
          logger.e('Failed to sync drive ${drive.id}', e);

          final updatedFailedDrives =
              List<String>.from(syncProgress.failedDriveIds)..add(drive.id);
          final updatedErrorMessages =
              Map<String, String>.from(syncProgress.errorMessages)
                ..putIfAbsent(drive.id, () => _extractErrorMessage(e));

          // Still increment progress but mark as failed (cap at 90%)
          totalProgress += 1;
          syncProgress = syncProgress.copyWith(
            drivesSynced: syncProgress.drivesSynced + 1,
            progress: (totalProgress / numberOfDrivesToSync) * 0.9,
            failedQueries: syncProgress.failedQueries + 1,
            failedDriveIds: updatedFailedDrives,
            errorMessages: updatedErrorMessages,
          );
          syncProgressController.add(syncProgress);
        }
      }),
      eagerError: false, // Continue processing even if some drives fail
    ).then((_) async {
      try {
        // If sync was cancelled during drive sync, add error to stream
        if (wasCancelled) {
          logger.d(
              'Sync was cancelled during drive sync, adding error to stream');
          // Clear the maps on cancellation to prevent state issues
          _ghostFolders.clear();
          _folderIds.clear();
          syncProgressController.addError(SyncCancelledException());
          await syncProgressController.close();
          return; // Exit early
        }

        // Check if we should skip post-sync operations due to failures
        final successfulSyncs =
            syncProgress.drivesSynced - syncProgress.failedQueries;
        if (successfulSyncs == 0) {
          logger.w('All drives failed to sync. Skipping post-sync operations.');
          logger.d('Closing sync progress controller due to all failures');
          await syncProgressController.close();
          return; // Exit early if all drives failed
        }

        // Continue with post-sync operations only if at least some drives succeeded
        logger.i('Creating ghosts...');

        // Check for cancellation before ghost creation
        token.checkCancellation();

        // Update progress to 92% for ghost creation
        syncProgress = syncProgress.copyWith(
          progress: 0.92,
          statusMessage: 'Creating ghost folders...',
        );
        syncProgressController.add(syncProgress);

        await createGhosts(
          driveDao: _driveDao,
          ownerAddress: await wallet?.getAddress(),
          ghostFolders: _ghostFolders,
        );

        /// Clear the ghost folders after they are created
        _ghostFolders.clear();

        /// Clear the folder ids after they are created
        _folderIds.clear();

        logger.i('Ghosts created...');

        logger.i('Syncing licenses...');

        // Check for cancellation before license sync
        token.checkCancellation();

        // Update progress to 94% for license sync
        syncProgress = syncProgress.copyWith(
          progress: 0.94,
          statusMessage: 'Syncing licenses...',
        );
        syncProgressController.add(syncProgress);

        try {
          final licenseTxIds = <String>{};
          final revisionsToSyncLicense = (await _driveDao
              .allFileRevisionsWithLicenseReferencedButNotSynced()
              .get())
            ..retainWhere((rev) => licenseTxIds.add(rev.licenseTxId!));
          logger.d('Found ${revisionsToSyncLicense.length} licenses to sync');

          await _updateLicenses(
            revisionsToSyncLicense: revisionsToSyncLicense,
          );
        } catch (e) {
          // Re-throw cancellation exceptions
          if (e is SyncCancelledException) {
            rethrow;
          }
          logger.e('Error syncing licenses. Proceeding.', e);
        }

        logger.i('Licenses synced');

        logger.i('Updating transaction statuses...');

        // Check for cancellation before transaction status updates
        token.checkCancellation();

        // Update progress to 96% for transaction status updates
        syncProgress = syncProgress.copyWith(
          progress: 0.96,
          statusMessage: 'Updating transaction statuses...',
        );
        syncProgressController.add(syncProgress);

        final allFileRevisions = await _getAllFileEntities(driveDao: _driveDao);
        final metadataTxsFromSnapshots =
            await SnapshotItemOnChain.getAllCachedTransactionIds();
        final confirmedFileTxIds = allFileRevisions
            .where(
                (file) => metadataTxsFromSnapshots.contains(file.metadataTxId))
            .map((file) => file.dataTxId)
            .toList();
        _arnsRepository
            .waitForARNSRecordsToUpdate()
            .then((value) => _arnsRepository.saveAllFilesWithAssignedNames());
        final hasHiddenItems = await _driveDao.hasHiddenItems().getSingle();
        await _userPreferencesRepository.saveUserHasHiddenItem(hasHiddenItems);
        await _userPreferencesRepository.load();
        // Wrap transaction status update with cancellation check and timeout
        try {
          await Future.wait(
            [
              _updateTransactionStatuses(
                driveDao: _driveDao,
                arweave: _arweave,
                txsIdsToSkip: confirmedFileTxIds,
                cancellationToken: token,
              ).timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  // Check if cancelled before timing out
                  token.checkCancellation();
                  logger.w(
                      'Transaction status update timed out after 10 seconds');
                  // Update status message to indicate timeout but don't treat as error
                  syncProgress = syncProgress.copyWith(
                    statusMessage: 'Completing sync...',
                  );
                  syncProgressController.add(syncProgress);
                  // Continue without updating transaction statuses
                },
              ),
            ],
          );
        } catch (e) {
          // Re-throw cancellation exceptions
          if (e is SyncCancelledException) {
            rethrow;
          }
          logger.w('Failed to update transaction statuses, continuing: $e');
          // Don't fail the entire sync if transaction status update fails
        }

        _lastSync = DateTime.now();

        // Update progress to 100% when truly complete
        syncProgress = syncProgress.copyWith(
          progress: 1.0,
          statusMessage: 'Sync complete',
        );
        syncProgressController.add(syncProgress);

        // Close the controller when everything is done
        logger.d('Sync completed successfully, closing controller');
        await syncProgressController.close();
      } catch (e) {
        // Handle cancellation during post-sync operations
        if (e is SyncCancelledException) {
          logger.i('Sync cancelled during post-sync operations');
          // Clear the maps on cancellation to prevent state issues
          _ghostFolders.clear();
          _folderIds.clear();
          syncProgressController
              .addError(e); // Add error to stream so cubit sees it
          await syncProgressController.close();
          return; // Don't rethrow - error is in stream
        }
        // Other errors - log and add to stream
        logger.e('Error during post-sync operations', e);
        // Clear the maps on any error to prevent state issues
        _ghostFolders.clear();
        _folderIds.clear();
        syncProgressController.addError(e);
        await syncProgressController.close();
        return;
      }
    }).catchError((error) async {
      // Clear the maps on any error to prevent state issues
      _ghostFolders.clear();
      _folderIds.clear();
      // Add error to stream and close
      logger.d('Sync failed with error, closing controller: $error');
      if (!syncProgressController.isClosed) {
        syncProgressController.addError(error);
        await syncProgressController.close();
      }
    });

    // Yield from the stream while the sync is happening
    yield* syncProgressController.stream;
  }

  String _extractErrorMessage(dynamic error) {
    if (error == null) return 'Unknown error';

    final errorStr = error.toString();

    // Check for common error patterns
    if (errorStr.contains('504')) {
      return 'Gateway timeout (504)';
    } else if (errorStr.contains('502')) {
      return 'Bad gateway (502)';
    } else if (errorStr.contains('503')) {
      return 'Service unavailable (503)';
    } else if (errorStr.contains('timeout')) {
      return 'Request timeout';
    } else if (errorStr.contains('GraphQL')) {
      return 'GraphQL query failed';
    } else if (errorStr.contains('network')) {
      return 'Network error';
    }

    // Return a truncated version of the error message
    return errorStr.length > 100
        ? '${errorStr.substring(0, 100)}...'
        : errorStr;
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

    // Collect all ghost folders to be created
    final ghostFoldersToCreate = <FolderEntry>[];

    //Finalize missing parent list
    for (final ghostFolder in ghostFolders.values) {
      final folder = await driveDao
          .folderById(folderId: ghostFolder.folderId)
          .getSingleOrNull();

      final folderExists = folder != null;

      if (folderExists) {
        continue;
      }

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
        lastUpdated: DateTime.now(),
        isGhost: true,
        dateCreated: DateTime.now(),
        isHidden: ghostFolder.isHidden,
        path: '',
      );
      ghostFoldersToCreate.add(folderEntry);
      ghostFoldersByDrive.putIfAbsent(
        drive.id,
        () => {folderEntry.id: folderEntry.toCompanion(false)},
      );
    }

    // Insert all ghost folders in a single transaction
    if (ghostFoldersToCreate.isNotEmpty) {
      await driveDao.transaction(() async {
        for (final folderEntry in ghostFoldersToCreate) {
          await driveDao.into(driveDao.folderEntries).insert(folderEntry);
        }
      });
    }
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
    SyncCancellationToken? cancellationToken,
  }) async {
    // Check for cancellation at the start
    cancellationToken?.checkCancellation();
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
      // Check for cancellation before each batch
      cancellationToken?.checkCancellation();

      final confirmations = <String?, int>{};
      final currentPage = <String>[];

      /// Mounts the list to be iterated
      for (var j = i * page; j < ((i + 1) * page); j++) {
        if (j >= length) {
          break;
        }
        currentPage.add(list[j]);
      }

      // Check cancellation before making the GraphQL call
      cancellationToken?.checkCancellation();

      // Use a shorter timeout for individual GraphQL calls
      final map = await arweave
          .getTransactionConfirmations(currentPage.toList())
          .timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          logger.w('Individual transaction confirmation timeout');
          // Return empty map on timeout to continue with other transactions
          return <String, int>{};
        },
      );

      map.forEach((key, value) {
        confirmations.putIfAbsent(key, () => value);
      });

      await driveDao.transaction(() async {
        for (final txId in currentPage) {
          // Check cancellation for each transaction
          cancellationToken?.checkCancellation();
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
    required String ownerAddress,
    Function(String driveId, int txCount)? txFechedCallback,
    SyncCancellationToken? cancellationToken,
  }) async* {
    final token = cancellationToken ?? SyncCancellationToken();

    /// Variables to count the current drive's progress information
    final drive = await _driveDao.driveById(driveId: driveId).getSingle();
    final startSyncDT = DateTime.now();

    logger.i('Syncing drive: ${drive.id}');

    DriveKey? driveKey;

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

    final transactions = <DriveEntityHistoryTransactionModel>[];

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

      List<SnapshotItem> snapshotsVerified =
          await _snapshotValidationService.validateSnapshotItems(snapshotItems);

      snapshotItems = snapshotsVerified;
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
    await for (DriveEntityHistoryTransactionModel t in transactionsStream) {
      // Check for cancellation periodically during transaction processing
      token.checkCancellation();
      double calculatePercentageBasedOnBlockHeights() {
        final block = t.transactionCommonMixin.block;

        if (block != null) {
          return (1 -
              ((currentBlockHeight - block.height) /
                  totalBlockHeightDifference));
        }

        /// if the block is null, we don't calculate and keep the same percentage
        return fetchPhasePercentage;
      }

      /// Initialize only once `firstBlockHeight` and `totalBlockHeightDifference`
      if (firstBlockHeight == null) {
        final block = t.transactionCommonMixin.block;

        if (block != null) {
          firstBlockHeight = block.height;
          totalBlockHeightDifference = currentBlockHeight - firstBlockHeight;
          logger.d(
            'First height: $firstBlockHeight, totalHeightDiff: $totalBlockHeightDifference',
          );
        } else {
          logger.d(
            'The transaction block is null. Transaction node id: ${t.transactionCommonMixin.id}',
          );
        }
      }

      transactions.add(t);

      /// We can only calculate the fetch percentage if we have the `firstBlockHeight`
      if (firstBlockHeight != null) {
        if (totalBlockHeightDifference > 0) {
          fetchPhasePercentage = calculatePercentageBasedOnBlockHeights();
        } else {
          // If the difference is zero means that the first phase was concluded.
          logger.d('The syncs first phase just finished!');
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
        transactions: transactions,
        drive: drive,
        driveKey: driveKey?.key,
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
    required List<DriveEntityHistoryTransactionModel> transactions,
    required Drive drive,
    required SecretKey? driveKey,
    required int lastBlockHeight,
    required int currentBlockHeight,
    required int batchSize,
    required SnapshotDriveHistory snapshotDriveHistory,
    // required Map<FolderID, GhostFolder> ghostFolders,
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

    yield* _batchProcessor.batchProcess<DriveEntityHistoryTransactionModel>(
        list: transactions,
        batchSize: batchSize,
        endOfBatchCallback: (items) async* {
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
              isHidden: Value(drive.isHidden),
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

            for (final entity in latestFileRevisions) {
              if (!_folderIds.contains(entity.parentFolderId.value)) {
                _ghostFolders.putIfAbsent(
                  entity.parentFolderId.value,
                  () => GhostFolder(
                    driveId: drive.id,
                    folderId: entity.parentFolderId.value,
                    isHidden: false,
                  ),
                );
              }
            }

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

            numberOfDriveEntitiesParsed +=
                updatedFoldersById.length + updatedFilesById.length;

            latestFolderRevisions.clear();
            latestFileRevisions.clear();
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
        // Gets the latest revision for the file, if it exists on the database.
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

        if (latestRevisions.containsKey(entity.id)) {
          final latestRevision = latestRevisions[entity.id];

          if (revision.dateCreated.value
              .isAfter(latestRevision!.dateCreated.value)) {
            latestRevisions[entity.id!] = revision;
            newRevisions.add(revision);
          }
        } else {
          latestRevisions[entity.id!] = revision;
          newRevisions.add(revision);
        }
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
    _folderIds.addAll(newEntities.map((e) => e.id!));
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

  @override
  Future<int> numberOfFilesInWallet() {
    return _driveDao.numberOfFiles();
  }

  @override
  Future<int> numberOfFoldersInWallet() {
    return _driveDao.numberOfFolders();
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
