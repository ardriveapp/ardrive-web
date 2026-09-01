import 'dart:async';
import 'dart:math';

import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/blocs/constants.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/drive_entity.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/entities/folder_entity.dart';
import 'package:ardrive/models/daos/drive_dao/drive_dao.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:ardrive/models/drive.dart';
import 'package:ardrive/models/drive_revision.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/models/file_revision.dart';
import 'package:ardrive/models/folder_revision.dart';
import 'package:ardrive/services/arweave/arweave.dart'
    hide SnapshotEntityTransaction;
import 'package:ardrive/services/config/config.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
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

/// Timeout for a single transaction-status confirmation batch
/// ([ArweaveService.getTransactionConfirmations]).
///
/// A gateway can be intermittently slow to answer a status query — a request may
/// take several seconds and still return valid data. This is set well above
/// typical response times so a slow-but-successful response isn't cancelled:
/// cancelling early discards the batch's confirmations and leaves
/// already-confirmed txs stuck showing as pending. Normal responses are fast, so
/// this only lengthens waits while a gateway is degraded — when we want to wait
/// rather than drop the batch. Partial progress is still preserved by the
/// verified sink regardless.
const _txConfirmationBatchTimeout = Duration(seconds: 15);

/// Overall timeout for a drive's transaction-status update (across batches).
/// Sits above [_txConfirmationBatchTimeout] so at least one slow-but-successful
/// batch can complete; remaining work resumes on the next sync.
const _txStatusUpdateTimeout = Duration(seconds: 30);

/// Where each phase of a sync ends on the 0..1 progress bar.
///
/// The split follows one rule: bar travel goes where progress is real. A phase
/// that reports what it has actually done gets room to report it; a phase that
/// cannot report gets almost none, because every point handed to it is a point
/// the bar crosses without knowing anything.
///
/// The walk keeps the large share. It is the only phase whose length grows
/// with the user's history, and the only one that already reports continuously
/// - per drive, and per block range inside a drive - so its share is the part
/// of the bar that genuinely tracks work. The four phases after it split the
/// remaining sixth between them by the same rule.
const _progressDriveWalkEnd = 0.85;

/// Ghost folder creation: local database writes over a map already in memory,
/// usually empty. A phase that flashes past does not get bar real estate it
/// cannot use, so the share is small - but it is not zero, because a drive
/// with hundreds of ghosts really does take a moment, and this reports per row
/// written.
const _progressGhostFoldersEnd = 0.88;

/// Reading what the snapshots already covered, and the hidden-item preference.
/// Local queries that already happen, reported per chunk read. Fast for most
/// wallets and slow for a few, so: a small share, spent granularly.
const _progressPendingScanEnd = 0.92;

/// The local half of the transaction-status phase: the pinned-data owner
/// overrides, the per-drive owners, the pending rows, and the date pre-load.
/// All local reads that were already being made and were counted in nothing
/// before. They report a step each, which is why this share is the largest of
/// the tail - it is the last stretch of the bar backed by finished work.
const _progressTxPrepEnd = 0.97;

/// Asking the gateway which pending transactions confirmed - the one phase in
/// the tail that leaves the machine, bounded only by [_txStatusUpdateTimeout].
///
/// It gets the smallest share of all, which is the opposite of what its
/// duration would suggest, and deliberate: it reports one step per 5000
/// pending transactions, so for a real user it reports exactly one step, when
/// the gateway answers. Points given to it would be points the bar crosses on
/// no evidence. Instead the bar goes indeterminate for the duration - see
/// [SyncProgress.isIndeterminate] - and this constant is only where the number
/// picks back up once the gateway is done with.
const _progressTxStatusEnd = 0.99;

/// The last hundredth is completion itself - the final writes and the summary
/// - so a finished sync says so by moving, not by having sat at the end for a
/// while already. Success lands here exactly.
const _progressComplete = 1.0;

/// What a single-drive sync calls the stretch between asking the gateway for
/// the drive's history and the first block height coming back.
///
/// Named rather than left blank because that stretch has no fraction to
/// report and the panel falls through to the percentage when there is no
/// phase - which is how the whole wait came to read "0% complete" without
/// moving. The all-drives path names each of its phases; this one is not
/// allowed to be the silent one.
const String _readingDriveHistoryMessage = 'Reading the drive history...';

/// Linear interpolation inside one phase's share of the bar, where [fraction]
/// is how much of that phase's own work is done.
double _phaseProgress(double start, double end, double fraction) =>
    start + (end - start) * fraction.clamp(0.0, 1.0);

/// The one place a sync's progress reaches the outside world.
///
/// Every emission passes through here, and `progress` is never published below
/// the highest value already published. A bar that jumps backwards reads as a
/// bug even when both numbers are individually defensible, and there is more
/// than one way to produce one here: drives sync concurrently over a shared
/// counter, and a single drive's progress is derived from block heights that a
/// composite history can hand back out of order. Enforcing the guarantee where
/// progress is published means no future caller can regress it by accident.
@visibleForTesting
class MonotonicProgressSink {
  final StreamController<SyncProgress> _controller =
      StreamController<SyncProgress>.broadcast();

  double _highWaterMark = 0;

  Stream<SyncProgress> get stream => _controller.stream;

  bool get isClosed => _controller.isClosed;

  /// Bounds and clamps without publishing, for the emissions a sync yields
  /// directly. Returns what the caller should go on holding as its progress.
  ///
  /// The bound to 0..1 is not defensive tidiness: a drive's walk progress is
  /// `1 - (head - blockHeight) / range`, and `head` is read once at the top of
  /// a sync that then runs for minutes. A transaction mined after that read
  /// sits above the head and makes the term negative, so the walk hands up a
  /// number greater than 1. Un-bounded, that number became the high-water mark
  /// and pinned every later emission - the whole tail, and "Sync complete"
  /// itself - to a bar that read 240% and never moved again.
  SyncProgress raise(SyncProgress progress) {
    final bounded = progress.progress.clamp(0.0, _progressComplete);
    if (bounded < _highWaterMark) {
      return progress.copyWith(progress: _highWaterMark);
    }
    _highWaterMark = bounded;
    return bounded == progress.progress
        ? progress
        : progress.copyWith(progress: bounded);
  }

  /// Clamps and publishes. Returns what was published, so the caller's copy
  /// and the listener's copy never disagree.
  ///
  /// Publishing to a closed controller throws, and this sink is reachable from
  /// work the sync has already stopped waiting for: `Future.timeout` does not
  /// cancel its source, so an abandoned `_updateTransactionStatuses` goes on
  /// issuing confirmation batches while the sync finishes and closes here. A
  /// throw there would abort the batches it had left, silently - the fired
  /// timeout swallows the error - and leave transaction statuses unwritten.
  /// Reporting stops at close; the work does not.
  SyncProgress add(SyncProgress progress) {
    final raised = raise(progress);
    if (!_controller.isClosed) {
      _controller.add(raised);
    }
    return raised;
  }

  void addError(Object error) {
    if (_controller.isClosed) {
      return;
    }
    _controller.addError(error);
  }

  Future<void> close() => _controller.close();
}

abstract class SyncRepository {
  /// The total transaction-parse budget, shared out across the drives still to
  /// be synced.
  @visibleForTesting
  static const maxTransactionParseBatchSize = 200;

  /// How many transactions each remaining drive may parse per batch.
  ///
  /// The budget is divided by the drives left to sync, so a wallet with more of
  /// them parses in smaller batches. Integer division makes that reach **zero**
  /// once more than [maxTransactionParseBatchSize] drives remain, and
  /// `BatchProcessor` throws `ArgumentError('Batch size cannot be 0')` on a
  /// batch of zero - so past that point a wallet could not sync at all, and the
  /// failure was an argument error rather than anything naming the cause.
  ///
  /// Clamped to at least one. A batch of one is slow; a batch of zero is a
  /// crash. No wallet is known to hold that many drives today, so this is a
  /// floor under a future scale rather than a fix for anyone's sync now.
  ///
  /// The subtraction is guarded too: `drivesSynced` reaching `drivesCount`
  /// would divide by zero, which throws a different error for the same reason.
  @visibleForTesting
  static int transactionParseBatchSizeFor({
    required int drivesCount,
    required int drivesSynced,
  }) {
    final remaining = drivesCount - drivesSynced;

    if (remaining <= 1) {
      return maxTransactionParseBatchSize;
    }

    return max(1, maxTransactionParseBatchSize ~/ remaining);
  }

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

  /// Syncs a single drive by its ID, with optional deep sync.
  /// Returns a stream of SyncProgress that can be used to track progress.
  Stream<SyncProgress> syncSingleDrive({
    required String driveId,
    bool syncDeep = false,
    Wallet? wallet,
    String? password,
    SecretKey? cipherKey,
    SyncCancellationToken? cancellationToken,
    Function(String driveId, int txCount)? txFechedCallback,
  });

  Stream<SyncProgress> syncAllDrives({
    bool syncDeep = false,
    Wallet? wallet,
    String? password,
    SecretKey? cipherKey,
    SyncCancellationToken? cancellationToken,
    List<String>? driveIdsToRetry,

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
    bool forceRefresh = false,

    /// Called as the drive listing is read, with how many have come back and
    /// how many there are. See [ArweaveService.getUniqueUserDriveEntities].
    void Function(int read, int found)? onDriveRead,
  });

  Future<void> createGhosts({
    required DriveDao driveDao,
    required Map<FolderID, GhostFolder> ghostFolders,
    String? ownerAddress,

    /// Called as each ghost row is written, with the fraction of them done.
    /// Reporting only; it changes nothing about what is written or in what
    /// order.
    void Function(double fraction)? onProgress,
  });

  Future<int> getCurrentBlockHeight();

  Future<int> numberOfFilesInWallet();
  Future<int> numberOfFoldersInWallet();

  /// Whether any transaction this wallet made is still unresolved - neither
  /// confirmed nor failed.
  ///
  /// A local database read against the status index and nothing else: this
  /// makes no network request. It is the signal that there is real work a sync
  /// would do, since resolving these is exactly what a sync does.
  ///
  /// Self-limiting, so a caller cannot be made to sync forever by it:
  /// `_updateTransactionStatuses` resolves a transaction to `confirmed` at
  /// [kRequiredTxConfirmationCount], or to `failed` once the gateway no longer
  /// knows it and it is past [kRequiredTxConfirmationPendingThreshold].
  Future<bool> hasPendingTransactions();

  factory SyncRepository({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ConfigService configService,
    required BatchProcessor batchProcessor,
    required SnapshotValidationService snapshotValidationService,
    required ARNSRepository arnsRepository,
    required UserPreferencesRepository userPreferencesRepository,
  }) {
    return _SyncRepository(
      arweave: arweave,
      driveDao: driveDao,
      configService: configService,
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
  final BatchProcessor _batchProcessor;
  final SnapshotValidationService _snapshotValidationService;
  final ARNSRepository _arnsRepository;
  final UserPreferencesRepository _userPreferencesRepository;

  final Map<String, GhostFolder> _ghostFolders = {};
  final Set<String> _folderIds = <String>{};

  /// Entities skipped this sync because their metadata could not be read,
  /// keyed by drive id. Reported on [SyncProgress] so a later pass can surface
  /// "failed files" in the UI.
  ///
  /// In-memory only — cleared at the start of each sync. Persisting these (so
  /// they are retried across syncs instead of relying on the 240-block
  /// look-back) is the follow-up described in
  /// `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`.
  final Map<String, Set<String>> _skippedEntityTxIdsByDrive = {};

  int get _skippedEntityCount => _skippedEntityTxIdsByDrive.values
      .fold(0, (sum, txIds) => sum + txIds.length);

  Map<String, List<String>> get _skippedEntityTxIdsByDriveSnapshot => {
        for (final entry in _skippedEntityTxIdsByDrive.entries)
          entry.key: [...entry.value],
      };

  void _recordSkippedEntities(String driveId, List<String> txIds) {
    if (txIds.isEmpty) return;
    _skippedEntityTxIdsByDrive
        .putIfAbsent(driveId, () => <String>{})
        .addAll(txIds);
  }

  /// Number of file and folder revisions this sync actually wrote to the
  /// database, keyed by drive id. Accumulated here for the same reason the
  /// skipped tx ids are: the write is the only place that knows what was
  /// written, and `SyncProgress.entitiesSynced` is otherwise a number nothing
  /// ever sets - it stayed 0 through a sync that pulled in five hundred files,
  /// and every surface built on it reported "nothing new".
  ///
  /// Taken from the revisions actually inserted, not from the lists the batch
  /// hands back. Those also carry revisions read from the cache for entities
  /// that turned out not to have changed, and every sync re-walks the last
  /// [kBlockHeightLookBack] blocks - so counting them would report a drive
  /// full of new items on a sync that wrote none.
  ///
  /// Ids, not revisions: one file arriving with three historical versions
  /// writes three revisions but is one item to the person reading the summary,
  /// and a first sync walks a drive's whole history.
  ///
  /// In-memory only - cleared at the start of each sync.
  final Map<String, Set<String>> _syncedEntityIdsByDrive = {};

  int get _syncedEntityCount =>
      _syncedEntityIdsByDrive.values.fold(0, (sum, ids) => sum + ids.length);

  /// Entity metadata bodies this sync has asked the gateway for, and how many
  /// of those have come back.
  ///
  /// One tally for the whole sync rather than one per drive: an all-drives
  /// sync runs its drives concurrently, and a per-drive figure would be
  /// several numbers taking turns in one line, each of them dropping when
  /// another drive got a word in. Both of these only ever climb.
  ///
  /// The total is what has been asked for so far, never a guess at the size of
  /// the drive: history arrives in chunks of
  /// [kStreamTransactionChunkSize] and only a chunk that has arrived can be
  /// counted. It rises as the walk finds more.
  ///
  /// In-memory only - reset at the start of each sync, exactly like
  /// [_syncedEntityIdsByDrive].
  int _metadataFetchesScheduled = 0;
  int _metadataFetchesCompleted = 0;


  void _resetMetadataFetchCounts() {
    _metadataFetchesScheduled = 0;
    _metadataFetchesCompleted = 0;
  }

  /// Entities written by the transaction currently open, not yet counted.
  ///
  /// The tally is what the user is shown as "N items changed" and what goes
  /// into the sync history, so it may only count what actually landed. These
  /// are recorded from inside `runTransaction`, before the commit - so a
  /// transaction that rolled back used to leave its rows counted anyway, and
  /// the sync reported changes the database never took.
  final Map<String, Set<String>> _pendingSyncedEntityIdsByDrive = {};

  void _recordSyncedEntities(String driveId, Iterable<String> entityIds) {
    if (entityIds.isEmpty) return;
    _pendingSyncedEntityIdsByDrive
        .putIfAbsent(driveId, () => <String>{})
        .addAll(entityIds);
  }

  /// Promotes what the just-committed transaction wrote into the tally.
  void _commitSyncedEntities() {
    for (final entry in _pendingSyncedEntityIdsByDrive.entries) {
      _syncedEntityIdsByDrive
          .putIfAbsent(entry.key, () => <String>{})
          .addAll(entry.value);
    }
    _pendingSyncedEntityIdsByDrive.clear();
  }

  /// Throws away what a transaction that did not commit had staged.
  void _discardPendingSyncedEntities() {
    _pendingSyncedEntityIdsByDrive.clear();
  }

  void _logSkippedEntities() {
    if (_skippedEntityTxIdsByDrive.isEmpty) return;
    logger.w(
      'Sync skipped $_skippedEntityCount entities across '
      '${_skippedEntityTxIdsByDrive.length} drive(s); their metadata could '
      'not be read from the configured gateway. '
      'See docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md',
    );
    for (final entry in _skippedEntityTxIdsByDrive.entries) {
      logger.w('Drive ${entry.key} skipped tx ids: ${entry.value.join(', ')}');
    }
  }

  /// Maximum number of transactions to hold in memory during streaming sync.
  /// Larger values = better throughput, higher memory usage
  /// Smaller values = lower memory usage, more frequent DB commits
  static const kStreamTransactionChunkSize = 1000;

  /// In-flight or completed [updateUserDrives] future to avoid redundant GQL
  /// calls when multiple entry points (syncMetadataOnly, startSync,
  /// startSyncForDrive) call it concurrently or in quick succession.
  /// Cleared after sync completes or when a drive is created/updated.
  Future<void>? _userDrivesUpdateFuture;

  DateTime? _lastSync;

  _SyncRepository({
    required ArweaveService arweave,
    required DriveDao driveDao,
    required ConfigService configService,
    required BatchProcessor batchProcessor,
    required SnapshotValidationService snapshotValidationService,
    required ARNSRepository arnsRepository,
    required UserPreferencesRepository userPreferencesRepository,
  })  : _arweave = arweave,
        _driveDao = driveDao,
        _configService = configService,
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
    List<String>? driveIdsToRetry,
  }) async* {
    final token = cancellationToken ?? SyncCancellationToken();

    // Clear shared state from any previous sync to prevent stale data
    _ghostFolders.clear();
    _folderIds.clear();
    _skippedEntityTxIdsByDrive.clear();
    _syncedEntityIdsByDrive.clear();
    _pendingSyncedEntityIdsByDrive.clear();
    _resetMetadataFetchCounts();

    // Every emission of this sync, from the first to the last, goes out
    // through one sink, so the number it reports can only ever climb.
    final syncProgressController = MonotonicProgressSink();

    // The address of the currently logged-in wallet. All pending transactions
    // are uploads made by this wallet, so scoping the status query by it lets
    // the gateway prune its search space. Cross-owner txs (e.g. data txs of
    // files pinned from other authors) won't match this owner; those that we
    // can identify locally are re-queried scoped to their real owner via
    // ownerOverrides in getTransactionConfirmations.
    String? walletAddress;
    if (wallet != null) {
      walletAddress = await wallet.getAddress();

      _arnsRepository
          .getAntRecordsForWallet(walletAddress, update: true)
          .catchError((e) {
        logger.e('Error getting ANT records for wallet. Continuing...', e);
        return Future.value(<ANTRecord>[]);
      });
    }

    // Sync the contents of each drive attached in the app.
    var drives = await _driveDao.allDrives().map((d) => d).get();

    // If retrying specific drives, filter to only those
    if (driveIdsToRetry != null && driveIdsToRetry.isNotEmpty) {
      final retrySet = driveIdsToRetry.toSet();
      drives = drives.where((d) => retrySet.contains(d.id)).toList();
    }

    if (drives.isEmpty) {
      yield syncProgressController.raise(SyncProgress.emptySyncCompleted());
      _lastSync = DateTime.now();
      return;
    }

    SyncProgress syncProgress =
        SyncProgress.initial().copyWith(drivesCount: drives.length);

    yield syncProgress = syncProgressController.raise(syncProgress);

    // The first network call of a sync, and the one that has nothing local to
    // fall back on. Until now the dialog sat at 0% with nothing to say while a
    // slow gateway was asked for the chain head.
    syncProgress = syncProgress.copyWith(
      statusMessage: 'Connecting to the network...',
    );
    yield syncProgress = syncProgressController.raise(syncProgress);

    final currentBlockHeight = await retry(
      () async => await _arweave.getCurrentBlockHeight(),
      onRetry: (exception) => logger.w(
        'Retrying for get the current block height',
      ),
    );

    // Probe for drive activity to skip unchanged drives.
    // Partition drives: never-synced drives always need full sync and would
    // poison the probe's minBlockHeight to 0 (causing it to query from genesis,
    // overflow the page limit, and fall back to syncing ALL drives).
    List<Drive> drivesToSync;
    if (syncDeep) {
      drivesToSync = drives;
      // A deep sync passes lastBlockHeight: 0 for every drive below, so every
      // drive is read from the start of its history - not just the ones that
      // have never been synced. Nothing is skipped, so skippedDriveCount is
      // left at its zero default.
      syncProgress = syncProgress.copyWith(
        firstTimeSyncDriveCount: drives.length,
      );
    } else {
      syncProgress = syncProgress.copyWith(
        statusMessage: 'Checking for changes...',
      );
      yield syncProgress = syncProgressController.raise(syncProgress);
      try {
        final neverSyncedDrives = <Drive>[];
        final previouslySyncedDrives = <Drive>[];

        for (final drive in drives) {
          if ((drive.lastBlockHeight ?? 0) == 0) {
            neverSyncedDrives.add(drive);
          } else {
            previouslySyncedDrives.add(drive);
          }
        }

        // Never-synced drives always need full sync
        drivesToSync = [...neverSyncedDrives];

        if (previouslySyncedDrives.isEmpty) {
          // All drives are never-synced; skip probe entirely
          if (neverSyncedDrives.isNotEmpty) {
            logger.i('${neverSyncedDrives.length} drives need first-time sync');
          }
          syncProgress = syncProgress.copyWith(
            firstTimeSyncDriveCount: neverSyncedDrives.length,
          );
        } else {
          // Group previously-synced drives by owner for efficient probing
          final drivesByOwner = <String, List<Drive>>{};
          for (final drive in previouslySyncedDrives) {
            drivesByOwner.putIfAbsent(drive.ownerAddress, () => []).add(drive);
          }

          final activeDriveIds = <String>{};
          bool allComplete = true;

          for (final entry in drivesByOwner.entries) {
            token.checkCancellation();
            final ownerDrives = entry.value;
            final minBlock = ownerDrives
                .map((d) =>
                    _calculateSyncLastBlockHeight(d.lastBlockHeight ?? 0))
                .reduce(min);

            final result = await _arweave.probeActiveDriveIds(
              driveIds: ownerDrives.map((d) => d.id).toList(),
              minBlockHeight: minBlock,
              ownerAddress: entry.key,
            );

            activeDriveIds.addAll(result.activeDriveIds);
            if (!result.isComplete) allComplete = false;
          }

          if (!allComplete) {
            // Can't confirm all drives checked — sync all previously-synced
            for (final drive in previouslySyncedDrives) {
              activeDriveIds.add(drive.id);
            }
          }

          // Add previously-synced drives that have activity
          drivesToSync.addAll(
            previouslySyncedDrives.where((d) => activeDriveIds.contains(d.id)),
          );

          final skipped = drives.length - drivesToSync.length;
          if (skipped > 0) {
            logger.i('Skipping $skipped unchanged drives');
          }
          if (neverSyncedDrives.isNotEmpty) {
            logger.i('${neverSyncedDrives.length} drives need first-time sync');
          }
          syncProgress = syncProgress.copyWith(
            firstTimeSyncDriveCount: neverSyncedDrives.length,
            skippedDriveCount: skipped,
          );
        }
      } catch (e) {
        logger.w('Drive activity probe failed, syncing all drives: $e');
        drivesToSync = drives;
        // The probe could not answer, so every drive is synced and none is
        // skipped. Each still walks from its own watermark, so the drives read
        // from the start of their history are exactly the never-synced ones.
        syncProgress = syncProgress.copyWith(
          firstTimeSyncDriveCount:
              drives.where((d) => (d.lastBlockHeight ?? 0) == 0).length,
          skippedDriveCount: 0,
        );
      }
    }

    // Clear the probe status message
    syncProgress = syncProgress.copyWith(statusMessage: null);
    yield syncProgress = syncProgressController.raise(syncProgress);

    final numberOfDrivesToSync = drivesToSync.length;

    if (numberOfDrivesToSync == 0) {
      // Probe found no drives with activity — this is a successful no-op sync
      logger.i('No drives need syncing');
      // Carry the probe's counts through. "Nothing to do" is exactly the sync
      // where the number of drives it skipped is the whole story.
      yield syncProgressController.raise(
        SyncProgress.emptySyncCompleted().copyWith(
          firstTimeSyncDriveCount: syncProgress.firstTimeSyncDriveCount,
          skippedDriveCount: syncProgress.skippedDriveCount,
        ),
      );
      _lastSync = DateTime.now();
      return;
    }

    syncProgress = syncProgress.copyWith(drivesCount: numberOfDrivesToSync);
    yield syncProgress = syncProgressController.raise(syncProgress);

    // Batch-fetch snapshots for all drives per owner (1 GQL query per owner
    // instead of 1 per drive). Results are grouped by Drive-Id and passed to
    // each drive's sync to avoid redundant per-drive snapshot queries.
    final prefetchedSnapshots = <String, List<SnapshotEntityTransaction>>{};
    if (_configService.config.enableSyncFromSnapshot && !syncDeep) {
      // The single largest download of a sync - tens of MB for a wallet with
      // history - and the longest stretch of it that said nothing at all.
      syncProgress = syncProgress.copyWith(
        statusMessage: 'Downloading drive snapshots...',
      );
      yield syncProgress = syncProgressController.raise(syncProgress);

      try {
        // Reuse the drivesByOwner grouping from the probe (or rebuild it)
        final snapshotDrivesByOwner = <String, List<Drive>>{};
        for (final drive in drivesToSync) {
          snapshotDrivesByOwner
              .putIfAbsent(drive.ownerAddress, () => [])
              .add(drive);
        }

        for (final entry in snapshotDrivesByOwner.entries) {
          final ownerDrives = entry.value;
          // Use only previously-synced drives for minBlock so never-synced
          // drives (lastBlockHeight=0) don't drag the query back to genesis.
          final syncedHeights = ownerDrives
              .where((d) => (d.lastBlockHeight ?? 0) > 0)
              .map(
                  (d) => _calculateSyncLastBlockHeight(d.lastBlockHeight ?? 0));
          final minBlock =
              syncedHeights.isNotEmpty ? syncedHeights.reduce(min) : 0;

          var queryFailed = false;
          final snapshotsStream = _arweave.getAllSnapshotsForDrives(
            ownerDrives.map((d) => d.id).toList(),
            minBlock,
            ownerAddress: entry.key,
            onQueryFailure: () => queryFailed = true,
          );

          await for (final snapshot in snapshotsStream) {
            final driveIdTag = snapshot.tags
                .where((t) => t.name == 'Drive-Id')
                .firstOrNull
                ?.value;
            if (driveIdTag != null) {
              prefetchedSnapshots
                  .putIfAbsent(driveIdTag, () => [])
                  .add(snapshot);
            } else {
              logger.w('Snapshot ${snapshot.id} has no Drive-Id tag, skipping');
            }
          }

          // Record an answer for every drive the query covered, including the
          // ones it found nothing for. `_syncDrive` reads a missing entry as
          // "nobody asked" and asks again per drive, so without this a drive
          // with no snapshots pays for a second, identical query on every
          // sync - the batch already told us the answer was none.
          //
          // Only when the query ran to completion: if it gave up part-way, a
          // drive it never reached would be recorded as having none, and the
          // per-drive fallback that exists for exactly that case would be
          // suppressed.
          if (!queryFailed) {
            for (final drive in ownerDrives) {
              prefetchedSnapshots.putIfAbsent(drive.id, () => []);
            }
          }
        }

        final withSnapshots =
            prefetchedSnapshots.values.where((v) => v.isNotEmpty).length;
        logger.i('[snapshot] prefetched '
            '${prefetchedSnapshots.values.expand((v) => v).length} '
            'for $withSnapshots of ${prefetchedSnapshots.length} drive(s); '
            'the rest are known to have none and will not be re-queried');
      } catch (e) {
        logger.w('Snapshot prefetch failed, will fetch per-drive: $e');
        prefetchedSnapshots.clear();
      }

      // Clear the prefetch status message
      syncProgress = syncProgress.copyWith(statusMessage: null);
      yield syncProgress = syncProgressController.raise(syncProgress);
    }

    double totalProgress = 0;

    // Reset the failure simulator for new sync session
    if (SyncFailureSimulator.instance.isEnabled) {
      SyncFailureSimulator.instance.resetFirstDrive();
    }

    // Track if sync was cancelled
    bool wasCancelled = false;

    // The one thing that moves during the drive walk's longest stretch.
    //
    // Published from inside the fetch loop rather than from the `await for`
    // below, because that loop only turns when a batch has been parsed and
    // written - which is after the whole batch's HTTP round trips are done,
    // and those round trips are nearly all of the phase.
    void reportMetadataFetchProgress() {
      syncProgress = syncProgress.copyWith(
        metadataFetchesCompleted: _metadataFetchesCompleted,
        metadataFetchesTotal: _metadataFetchesScheduled,
      );
      syncProgress = syncProgressController.add(syncProgress);
    }

    // Start the async work but don't wait for it yet
    // Using Future.wait with eagerError: false to continue even if some drives fail
    Future.wait(
      drivesToSync.map((drive) async {
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
                : _calculateSyncLastBlockHeight(drive.lastBlockHeight ?? 0),
            currentBlockHeight: currentBlockHeight,
            transactionParseBatchSize: _transactionParseBatchSize(syncProgress),
            ownerAddress: drive.ownerAddress,
            txFechedCallback: txFechedCallback,
            cancellationToken: token,
            prefetchedSnapshots: prefetchedSnapshots[drive.id],
            skipPendingTxFetch:
                walletAddress != null && drive.ownerAddress != walletAddress,
            onMetadataFetchProgress: reportMetadataFetchProgress,
          );

          double currentDriveProgress = 0;
          await for (var driveProgress in driveSyncProgress) {
            // Check for cancellation during sync
            token.checkCancellation();

            // The walk's whole share of the bar, divided across the drives
            // in it. The sink guards the ordering - these drives run
            // concurrently over a shared counter, and a drive's own progress
            // is read off block heights a composite history can hand back out
            // of order - but the ceiling has to be applied here, at the phase
            // it belongs to. A transaction mined after the head was read
            // yields a drive progress above 1, and a walk value above the
            // walk's end would become the high-water mark and pin the whole
            // tail behind it without ever exceeding 1.0.
            currentDriveProgress = ((totalProgress + driveProgress) /
                    numberOfDrivesToSync *
                    _progressDriveWalkEnd)
                .clamp(0.0, _progressDriveWalkEnd);
            syncProgress = syncProgress.copyWith(
              progress: currentDriveProgress,
              // Live, for the same reason as the single-drive walk: a count
              // that can only rise is a better thing to watch than a fraction
              // that cannot move.
              entitiesSynced: _syncedEntityCount,
            );
            syncProgress = syncProgressController.add(syncProgress);
          }
          totalProgress += 1;
          syncProgress = syncProgress.copyWith(
            drivesSynced: syncProgress.drivesSynced + 1,
            // Recorded only on the path that got to the end. The catch below
            // increments the same counters for a drive that failed, and a
            // drive that failed has not been synced.
            syncedDriveIds: [...syncProgress.syncedDriveIds, drive.id],
            progress:
                (totalProgress / numberOfDrivesToSync) * _progressDriveWalkEnd,
          );
          syncProgress = syncProgressController.add(syncProgress);
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
          final updatedErrorMessages = Map<String, String>.from(
              syncProgress.errorMessages)
            ..putIfAbsent(
                drive.id, () => '${drive.name}: ${_extractErrorMessage(e)}');

          // Still increment progress but mark as failed
          totalProgress += 1;
          syncProgress = syncProgress.copyWith(
            drivesSynced: syncProgress.drivesSynced + 1,
            progress:
                (totalProgress / numberOfDrivesToSync) * _progressDriveWalkEnd,
            failedQueries: syncProgress.failedQueries + 1,
            failedDriveIds: updatedFailedDrives,
            errorMessages: updatedErrorMessages,
          );
          syncProgress = syncProgressController.add(syncProgress);
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

        // The walk is over, so this phase starts where the walk ended
        // rather than skipping past it.
        syncProgress = syncProgress.copyWith(
          progress: _progressDriveWalkEnd,
          statusMessage: 'Creating ghost folders...',
          // Given back with the walk that owned it. Left set, "Reading n of n"
          // would sit on top of every phase that follows - all of which have
          // something of their own to say.
          metadataFetchesCompleted: 0,
          metadataFetchesTotal: 0,
        );
        syncProgress = syncProgressController.add(syncProgress);

        await createGhosts(
          driveDao: _driveDao,
          ownerAddress: await wallet?.getAddress(),
          ghostFolders: _ghostFolders,
          onProgress: (fraction) {
            syncProgress = syncProgress.copyWith(
              progress: _phaseProgress(
                _progressDriveWalkEnd,
                _progressGhostFoldersEnd,
                fraction,
              ),
            );
            syncProgress = syncProgressController.add(syncProgress);
          },
        );

        // Ghosts are done whether there were any to write or not, so the
        // phase closes on its own boundary instead of leaving the bar
        // wherever the loop happened to stop.
        syncProgress = syncProgress.copyWith(
          progress: _progressGhostFoldersEnd,
        );
        syncProgress = syncProgressController.add(syncProgress);

        /// Clear the ghost folders after they are created
        _ghostFolders.clear();

        /// Clear the folder ids after they are created
        _folderIds.clear();

        logger.i('Ghosts created...');

        // License sync removed — licenses are now fetched on-demand when the
        // user views file details. This avoids thousands of GraphQL queries
        // during sync for display-only data.

        logger.i('Updating transaction statuses...');

        // Check for cancellation before transaction status updates
        token.checkCancellation();

        syncProgress = syncProgress.copyWith(
          progress: _progressGhostFoldersEnd,
          statusMessage: 'Updating transaction statuses...',
        );
        syncProgress = syncProgressController.add(syncProgress);

        final metadataTxsFromSnapshots =
            await SnapshotItemOnChain.getAllCachedTransactionIds();
        final confirmedFileTxIds = <String>[];
        if (metadataTxsFromSnapshots.isNotEmpty) {
          final chunkCount = (metadataTxsFromSnapshots.length / 500).ceil();
          var chunksRead = 0;
          for (var i = 0; i < metadataTxsFromSnapshots.length; i += 500) {
            final chunk = metadataTxsFromSnapshots.sublist(
                i, min(i + 500, metadataTxsFromSnapshots.length));
            final rows = await _driveDao
                .fileRevisionDataTxIdsByMetadataTxIds(metadataTxIds: chunk)
                .get();
            confirmedFileTxIds.addAll(rows);
            // One chunk read is one step of this phase - reported off the
            // query that was already being made, not a new one.
            chunksRead++;
            syncProgress = syncProgress.copyWith(
              progress: _phaseProgress(
                _progressGhostFoldersEnd,
                _progressPendingScanEnd,
                chunksRead / chunkCount,
              ),
            );
            syncProgress = syncProgressController.add(syncProgress);
          }
        }
        // Clear cached transaction IDs now that we've used them
        SnapshotItemOnChain.clearAllCachedTransactionIds();
        _arnsRepository
            .waitForARNSRecordsToUpdate()
            .then((value) => _arnsRepository.saveAllFilesWithAssignedNames());
        final hasHiddenItems = await _driveDao.hasHiddenItems().getSingle();
        await _userPreferencesRepository.saveUserHasHiddenItem(hasHiddenItems);
        await _userPreferencesRepository.load();

        // Everything readable locally has been read; what is left is the
        // gateway.
        syncProgress = syncProgress.copyWith(
          progress: _progressPendingScanEnd,
        );
        syncProgress = syncProgressController.add(syncProgress);

        // Wrap transaction status update with cancellation check and timeout
        try {
          await Future.wait(
            [
              _updateTransactionStatuses(
                driveDao: _driveDao,
                arweave: _arweave,
                // Scope the gateway query to the logged-in wallet for selectivity.
                ownerAddress: walletAddress,
                txsIdsToSkip: confirmedFileTxIds,
                cancellationToken: token,
                onLocalProgress: (fraction) {
                  syncProgress = syncProgress.copyWith(
                    progress: _phaseProgress(
                      _progressPendingScanEnd,
                      _progressTxPrepEnd,
                      fraction,
                    ),
                  );
                  syncProgress = syncProgressController.add(syncProgress);
                },
                onProgress: (fraction) {
                  syncProgress = syncProgress.copyWith(
                    progress: _phaseProgress(
                      _progressTxPrepEnd,
                      _progressTxStatusEnd,
                      fraction,
                    ),
                  );
                  syncProgress = syncProgressController.add(syncProgress);
                },
                onGatewayPhase: (active) {
                  syncProgress = syncProgress.copyWith(isIndeterminate: active);
                  syncProgress = syncProgressController.add(syncProgress);
                },
              ).timeout(
                _txStatusUpdateTimeout,
                onTimeout: () {
                  // Check if cancelled before timing out
                  token.checkCancellation();
                  logger.w('Transaction status update timed out after '
                      '${_txStatusUpdateTimeout.inSeconds}s');
                  // Update status message to indicate timeout but don't treat as error
                  syncProgress = syncProgress.copyWith(
                    statusMessage: 'Completing sync...',
                    isIndeterminate: false,
                  );
                  syncProgress = syncProgressController.add(syncProgress);
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

        // The gateway is done with, however that went - answered, failed or
        // timed out. The phase closes on its boundary either way, because the
        // work after it is the completion itself, and the bar goes back to
        // being a number here whatever the loop did or did not manage to say.
        syncProgress = syncProgress.copyWith(
          progress: _progressTxStatusEnd,
          isIndeterminate: false,
        );
        syncProgress = syncProgressController.add(syncProgress);

        _lastSync = DateTime.now();
        // Invalidate drive caches so next sync re-fetches fresh data
        _userDrivesUpdateFuture = null;
        _arweave.clearUserDriveTxsCache();

        // Exactly 1.0, and only here.
        syncProgress = syncProgress.copyWith(
          progress: _progressComplete,
          statusMessage: 'Sync complete',
          entitiesSynced: _syncedEntityCount,
          skippedEntityCount: _skippedEntityCount,
          skippedEntityTxIdsByDrive: _skippedEntityTxIdsByDriveSnapshot,
        );
        syncProgress = syncProgressController.add(syncProgress);
        _logSkippedEntities();

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
  Stream<SyncProgress> syncSingleDrive({
    required String driveId,
    bool syncDeep = false,
    Wallet? wallet,
    String? password,
    SecretKey? cipherKey,
    SyncCancellationToken? cancellationToken,
    Function(String driveId, int txCount)? txFechedCallback,
  }) async* {
    final token = cancellationToken ?? SyncCancellationToken();

    // Clear shared state from any previous sync to prevent stale data
    _ghostFolders.clear();
    _folderIds.clear();
    _skippedEntityTxIdsByDrive.clear();
    _syncedEntityIdsByDrive.clear();
    _pendingSyncedEntityIdsByDrive.clear();
    _resetMetadataFetchCounts();

    // Every emission of this sync, from the first to the last, goes out
    // through one sink, so the number it reports can only ever climb.
    final syncProgressController = MonotonicProgressSink();

    // Get the specific drive
    final drive = await _driveDao.driveById(driveId: driveId).getSingleOrNull();
    if (drive == null) {
      yield syncProgressController.raise(SyncProgress.emptySyncCompleted());
      return;
    }

    SyncProgress syncProgress = SyncProgress.initial().copyWith(
      drivesCount: 1,
      isSingleDriveSync: true,
      driveName: drive.name,
      // Same question this path already answers below when it decides where to
      // start the walk: a deep sync reads from block zero, and so does a drive
      // that has never been synced. Set here rather than left at its default,
      // because a field that is only correct on the all-drives path is worse
      // than one that is absent - a caller cannot tell which it is holding.
      firstTimeSyncDriveCount:
          syncDeep || (drive.lastBlockHeight ?? 0) == 0 ? 1 : 0,
    );
    yield syncProgress = syncProgressController.raise(syncProgress);

    // Same silent first call as the all-drives path.
    syncProgress = syncProgress.copyWith(
      statusMessage: 'Connecting to the network...',
    );
    yield syncProgress = syncProgressController.raise(syncProgress);

    final currentBlockHeight = await retry(
      () async => await _arweave.getCurrentBlockHeight(),
      onRetry: (exception) => logger.w(
        'Retrying for get the current block height',
      ),
    );

    // The walk that follows is reported as a percentage - but not yet. Its
    // first fraction is read off a block height, and no block height exists
    // until the gateway has answered the whole first history query, which on a
    // never-walked drive is the longest single wait in the sync. Clearing the
    // message here is what put a motionless "0% complete" on screen for that
    // entire round trip: a figure the sync did not have, sitting still, which
    // is the one thing this panel exists to stop.
    //
    // So the phase names itself and the bar is told it has nothing to measure.
    // Both are given up the moment the walk reports a fraction of its own -
    // see walkHasMeasuredProgress below - and the percentage takes over
    // from there, exactly as it did.
    syncProgress = syncProgress.copyWith(
      statusMessage: _readingDriveHistoryMessage,
      isIndeterminate: true,
    );
    yield syncProgress = syncProgressController.raise(syncProgress);

    // Store ghost folders for this drive only
    final driveGhostFolders = <String, GhostFolder>{};

    // The one thing that moves while the drive's metadata is being fetched -
    // see the identical closure on the all-drives path.
    void reportMetadataFetchProgress() {
      syncProgress = syncProgress.copyWith(
        metadataFetchesCompleted: _metadataFetchesCompleted,
        metadataFetchesTotal: _metadataFetchesScheduled,
      );
      syncProgress = syncProgressController.add(syncProgress);
    }

    // Start the async work
    Future.microtask(() async {
      try {
        // Check for cancellation before starting
        token.checkCancellation();

        final walletAddress = await wallet?.getAddress();

        final driveSyncProgress = _syncDrive(
          drive.id,
          cipherKey: cipherKey,
          lastBlockHeight: syncDeep
              ? 0
              : _calculateSyncLastBlockHeight(drive.lastBlockHeight ?? 0),
          currentBlockHeight: currentBlockHeight,
          transactionParseBatchSize: 200,
          ownerAddress: drive.ownerAddress,
          txFechedCallback: txFechedCallback,
          cancellationToken: token,
          skipPendingTxFetch:
              walletAddress != null && drive.ownerAddress != walletAddress,
          onMetadataFetchProgress: reportMetadataFetchProgress,
        );

        // Whether the walk has yet produced a fraction that means something.
        // Until it has, the panel is showing a named phase and a sweeping bar
        // rather than a number; the first real measurement is what hands the
        // display back to the percentage.
        var walkHasMeasuredProgress = false;

        await for (var driveProgress in driveSyncProgress) {
          // Check for cancellation during sync
          token.checkCancellation();

          if (!walkHasMeasuredProgress && driveProgress > 0) {
            walkHasMeasuredProgress = true;

            syncProgress = syncProgress.copyWith(
              statusMessage: null,
              isIndeterminate: false,
            );
          }

          // The walk's whole share of the bar. The sink guards the ordering
          // - a drive's progress is read off block heights a composite
          // history can hand back out of order - but the ceiling belongs
          // here: a transaction mined after the head was read yields a drive
          // progress above 1, and a walk value above the walk's end would
          // pin every phase after it without ever exceeding 1.0.
          syncProgress = syncProgress.copyWith(
            progress: (driveProgress * _progressDriveWalkEnd)
                .clamp(0.0, _progressDriveWalkEnd),
            // The count is already accumulating per batch in
            // _recordSyncedEntities; it was only ever read at the final
            // emission. Published live it is a better number than the
            // percentage beside it: it needs no total, so it is honest from
            // the first batch, it can only go up, and it is in the user's own
            // units rather than blocks.
            entitiesSynced: _syncedEntityCount,
          );
          syncProgress = syncProgressController.add(syncProgress);
        }

        // The walk is over however it went, so whatever it was allowed to
        // withhold while it had nothing to measure is given back here: a walk
        // that ended without ever reporting a fraction must not leave the bar
        // sweeping into the phases that follow it.
        syncProgress = syncProgress.copyWith(
          drivesSynced: 1,
          syncedDriveIds: [driveId],
          progress: _progressDriveWalkEnd,
          statusMessage: null,
          isIndeterminate: false,
          // Given back with the walk that owned it, for the same reason the
          // sweeping bar is: nothing after this point is a metadata fetch.
          metadataFetchesCompleted: 0,
          metadataFetchesTotal: 0,
        );
        syncProgress = syncProgressController.add(syncProgress);

        // Copy ghost folders for this drive only
        for (final entry in _ghostFolders.entries) {
          if (entry.value.driveId == driveId) {
            driveGhostFolders[entry.key] = entry.value;
          }
        }

        // Check for cancellation before ghost creation
        token.checkCancellation();

        // The walk is over, so this phase starts where the walk ended
        // rather than skipping past it.
        syncProgress = syncProgress.copyWith(
          progress: _progressDriveWalkEnd,
          statusMessage: 'Creating ghost folders...',
        );
        syncProgress = syncProgressController.add(syncProgress);

        logger.i('Creating ghosts for single drive sync...');

        await createGhosts(
          driveDao: _driveDao,
          ownerAddress: await wallet?.getAddress(),
          ghostFolders: driveGhostFolders,
          onProgress: (fraction) {
            syncProgress = syncProgress.copyWith(
              progress: _phaseProgress(
                _progressDriveWalkEnd,
                _progressGhostFoldersEnd,
                fraction,
              ),
            );
            syncProgress = syncProgressController.add(syncProgress);
          },
        );

        // Ghosts are done whether there were any to write or not, so the
        // phase closes on its own boundary.
        syncProgress = syncProgress.copyWith(
          progress: _progressGhostFoldersEnd,
        );
        syncProgress = syncProgressController.add(syncProgress);

        // Remove processed ghost folders from the main map
        for (final key in driveGhostFolders.keys) {
          _ghostFolders.remove(key);
        }

        logger.i('Ghosts created for single drive...');

        // Check for cancellation before license sync
        token.checkCancellation();

        // License sync removed — fetched on-demand in file details panel.

        // Check for cancellation before transaction status updates
        token.checkCancellation();

        syncProgress = syncProgress.copyWith(
          progress: _progressGhostFoldersEnd,
          statusMessage: 'Updating transaction statuses...',
        );
        syncProgress = syncProgressController.add(syncProgress);

        logger.i('Updating transaction statuses for single drive...');

        // This phase's local reads: the drive's revisions, the transaction ids
        // the snapshots already covered, then the hidden-item preference.
        // Three steps, reported as each one lands. All three reads already
        // happened; only the reporting is new.
        const localReadCount = 3;
        var localReadsDone = 0;
        void reportLocalRead() {
          localReadsDone++;
          syncProgress = syncProgress.copyWith(
            progress: _phaseProgress(
              _progressGhostFoldersEnd,
              _progressPendingScanEnd,
              localReadsDone / localReadCount,
            ),
          );
          syncProgress = syncProgressController.add(syncProgress);
        }

        // Get file revisions for this specific drive to scope transaction updates
        final driveFileRevisions =
            await _driveDao.db.fileRevisions.select().get();
        reportLocalRead();
        final driveDataTxIds = driveFileRevisions
            .where((r) => r.driveId == driveId)
            .map((r) => r.dataTxId)
            .toSet();

        final metadataTxsFromSnapshots =
            await SnapshotItemOnChain.getAllCachedTransactionIds();
        reportLocalRead();
        final confirmedFileTxIds = driveFileRevisions
            .where((file) =>
                file.driveId == driveId &&
                metadataTxsFromSnapshots.contains(file.metadataTxId))
            .map((file) => file.dataTxId)
            .toList();

        // Clear cached transaction IDs for this drive
        SnapshotItemOnChain.clearAllCachedTransactionIds();

        // Check for hidden items in this drive and update preferences
        final hasHiddenItems = await _driveDao.hasHiddenItems().getSingle();
        await _userPreferencesRepository.saveUserHasHiddenItem(hasHiddenItems);
        await _userPreferencesRepository.load();
        reportLocalRead();

        try {
          await _updateTransactionStatusesForDrive(
            driveDao: _driveDao,
            arweave: _arweave,
            driveDataTxIds: driveDataTxIds,
            // Scope the gateway query to this drive's owner for selectivity.
            ownerAddress: drive.ownerAddress,
            txsIdsToSkip: confirmedFileTxIds,
            cancellationToken: token,
            onLocalProgress: (fraction) {
              syncProgress = syncProgress.copyWith(
                progress: _phaseProgress(
                  _progressPendingScanEnd,
                  _progressTxPrepEnd,
                  fraction,
                ),
              );
              syncProgress = syncProgressController.add(syncProgress);
            },
            onProgress: (fraction) {
              syncProgress = syncProgress.copyWith(
                progress: _phaseProgress(
                  _progressTxPrepEnd,
                  _progressTxStatusEnd,
                  fraction,
                ),
              );
              syncProgress = syncProgressController.add(syncProgress);
            },
            onGatewayPhase: (active) {
              syncProgress = syncProgress.copyWith(isIndeterminate: active);
              syncProgress = syncProgressController.add(syncProgress);
            },
          ).timeout(
            _txStatusUpdateTimeout,
            onTimeout: () {
              token.checkCancellation();
              logger.w('Transaction status update timed out after '
                  '${_txStatusUpdateTimeout.inSeconds}s for single drive');
              syncProgress = syncProgress.copyWith(
                statusMessage: 'Completing sync...',
                isIndeterminate: false,
              );
              syncProgress = syncProgressController.add(syncProgress);
            },
          );
        } catch (e) {
          if (e is SyncCancelledException) {
            rethrow;
          }
          logger.w(
              'Failed to update transaction statuses for single drive, continuing: $e');
        }

        // The gateway is done with, however that went. The phase closes on its
        // boundary either way, because the work after it is the completion,
        // and the bar goes back to being a number here regardless.
        syncProgress = syncProgress.copyWith(
          progress: _progressTxStatusEnd,
          isIndeterminate: false,
        );
        syncProgress = syncProgressController.add(syncProgress);

        _lastSync = DateTime.now();
        // Invalidate drive caches so next sync re-fetches fresh data
        _userDrivesUpdateFuture = null;
        _arweave.clearUserDriveTxsCache();

        // Exactly 1.0, and only here.
        syncProgress = syncProgress.copyWith(
          progress: _progressComplete,
          statusMessage: 'Sync complete',
          entitiesSynced: _syncedEntityCount,
          skippedEntityCount: _skippedEntityCount,
          skippedEntityTxIdsByDrive: _skippedEntityTxIdsByDriveSnapshot,
        );
        syncProgress = syncProgressController.add(syncProgress);
        _logSkippedEntities();

        logger
            .d('Single drive sync completed successfully, closing controller');
        await syncProgressController.close();
      } catch (e) {
        if (e is SyncCancelledException) {
          logger.i('Single drive sync cancelled');
          // Clear per-sync state to prevent leaking into subsequent runs
          driveGhostFolders.clear();
          _folderIds.clear();
          // Remove any ghost folders for this drive from the instance map
          _ghostFolders.removeWhere((_, v) => v.driveId == driveId);
          syncProgressController.addError(e);
          await syncProgressController.close();
          return;
        }

        // Track the failure
        logger.e('Failed to sync drive $driveId', e);

        // Clear per-sync state on error to prevent leaking into subsequent runs
        driveGhostFolders.clear();
        _folderIds.clear();
        // Remove any ghost folders for this drive from the instance map
        _ghostFolders.removeWhere((_, v) => v.driveId == driveId);

        final updatedErrorMessages =
            Map<String, String>.from(syncProgress.errorMessages)
              ..putIfAbsent(
                  driveId, () => '${drive.name}: ${_extractErrorMessage(e)}');

        // Whatever phase the sync was in, it is not in it any more. A
        // terminal emission that still names the wait it died during - and
        // still tells the bar it cannot be measured - describes work nothing
        // is doing.
        syncProgress = syncProgress.copyWith(
          drivesSynced: 1,
          progress: _progressComplete,
          failedQueries: 1,
          failedDriveIds: [driveId],
          errorMessages: updatedErrorMessages,
          statusMessage: null,
          isIndeterminate: false,
        );
        syncProgress = syncProgressController.add(syncProgress);
        await syncProgressController.close();
      }
    }).catchError((error) async {
      // Clear per-sync state on error to prevent leaking into subsequent runs
      driveGhostFolders.clear();
      _folderIds.clear();
      // Remove any ghost folders for this drive from the instance map
      _ghostFolders.removeWhere((_, v) => v.driveId == driveId);
      logger
          .d('Single drive sync failed with error, closing controller: $error');
      if (!syncProgressController.isClosed) {
        syncProgressController.addError(error);
        await syncProgressController.close();
      }
    });

    // Yield from the stream while the sync is happening
    yield* syncProgressController.stream;
  }

  /// Updates transaction statuses scoped to a specific drive's transactions
  Future<void> _updateTransactionStatusesForDrive({
    required DriveDao driveDao,
    required ArweaveService arweave,
    required Set<String> driveDataTxIds,
    String? ownerAddress,
    List<TxID> txsIdsToSkip = const [],
    SyncCancellationToken? cancellationToken,

    /// Called as this phase's local database reads land, with the fraction of
    /// them done. Both already happened; only the reporting is new.
    void Function(double fraction)? onLocalProgress,

    /// Called as the rest of the phase lands - the date pre-load chunks and
    /// each gateway confirmation batch - with the fraction of it done.
    /// Reporting only.
    void Function(double fraction)? onProgress,

    /// Called with true when the gateway confirmation loop begins and false
    /// when it is over. See [_updateTransactionStatuses].
    void Function(bool active)? onGatewayPhase,
  }) async {
    cancellationToken?.checkCancellation();

    // The two local reads this phase makes before it touches the gateway,
    // reported as each lands. Both were already being made.
    const localReadCount = 2;
    var localReadsDone = 0;
    void reportLocalRead() {
      localReadsDone++;
      onLocalProgress?.call(localReadsDone / localReadCount);
    }

    final ownerOverrides = await _buildPinnedDataTxOwnerOverrides(driveDao);
    reportLocalRead();

    // Load all pending transactions and filter to this drive
    final allPendingTxs = await driveDao.pendingTransactions().get();
    reportLocalRead();
    final drivePendingTxs =
        allPendingTxs.where((tx) => driveDataTxIds.contains(tx.id)).toList();

    logger.i(
        'Loaded ${drivePendingTxs.length} pending transactions for drive (from ${allPendingTxs.length} total)');

    final pendingTxMap = <String, NetworkTransaction>{
      for (final tx in drivePendingTxs) tx.id: tx,
    };

    // Remove transactions to skip
    for (final txId in txsIdsToSkip) {
      pendingTxMap.remove(txId);
    }

    // Bulk pre-load dateCreated for pending txs missing it (avoids N+1 queries)
    final txIdsNeedingDates = pendingTxMap.entries
        .where((e) => e.value.transactionDateCreated == null)
        .map((e) => e.key)
        .toList();

    // What is left of the phase after the local reads above, counted off the
    // work it already does: one step per date pre-load chunk, one per
    // confirmation batch. No extra query, and no invented ramp - a phase with
    // a single batch reports a single step, because a single step is what it
    // has. Finer detail than this lives inside the gateway call itself and
    // would mean changing ArweaveService, which is why the gateway stretch is
    // drawn as indeterminate rather than as a number.
    const page = 5000;
    final totalSteps = (txIdsNeedingDates.length / 500).ceil() +
        (pendingTxMap.length / page).ceil();
    var stepsDone = 0;
    void reportStep() {
      if (totalSteps == 0) return;
      stepsDone++;
      onProgress?.call(stepsDone / totalSteps);
    }

    final dateCreatedCache = <String, DateTime?>{};
    if (txIdsNeedingDates.isNotEmpty) {
      for (var i = 0; i < txIdsNeedingDates.length; i += 500) {
        final chunk = txIdsNeedingDates.sublist(
            i, min(i + 500, txIdsNeedingDates.length));
        final rows = await driveDao
            .fileRevisionDateCreatedByDataTxIds(txIds: chunk)
            .get();
        for (final row in rows) {
          dateCreatedCache[row.dataTxId] = row.dateCreated;
        }
        reportStep();
      }
    }

    final length = pendingTxMap.length;
    final list = pendingTxMap.keys.toList();

    // From here the phase belongs to the gateway, and how long it takes is
    // the gateway's to know. Rather than cross points of the bar on no
    // evidence, the bar goes indeterminate for the duration and picks the
    // number back up on the far side - however that side is reached.
    final batchCount = (length / page).ceil();
    if (batchCount > 0) {
      onGatewayPhase?.call(true);
    }

    for (var i = 0; i < length / page; i++) {
      cancellationToken?.checkCancellation();

      final confirmations = <String?, int>{};
      final currentPage = <String>[];

      for (var j = i * page; j < ((i + 1) * page); j++) {
        if (j >= length) {
          break;
        }
        currentPage.add(list[j]);
      }

      cancellationToken?.checkCancellation();

      // Caller-owned sink populated with each resolved confirmation; on timeout
      // we fall back to it so progress made before the deadline isn't lost.
      final verified = <String?, int>{};

      final map = await arweave
          .getTransactionConfirmations(currentPage.toList(),
              owner: ownerAddress,
              ownerOverrides: ownerOverrides,
              verifiedSink: verified)
          .timeout(
        _txConfirmationBatchTimeout,
        onTimeout: () {
          logger.w('Individual transaction confirmation timeout; '
              'applying ${verified.length} confirmations resolved so far');
          return verified;
        },
      );

      map.forEach((key, value) {
        confirmations.putIfAbsent(key, () => value);
      });

      final updates = <NetworkTransactionsCompanion>[];
      for (final txId in currentPage) {
        cancellationToken?.checkCancellation();

        // Skip if confirmation data is missing (e.g., timeout or partial response)
        final confirmationCount = confirmations[txId];
        if (confirmationCount == null) {
          continue;
        }

        final txConfirmed = confirmationCount >= kRequiredTxConfirmationCount;
        final txNotFound = confirmationCount < 0;

        String? txStatus;
        DateTime? transactionDateCreated;

        if (pendingTxMap[txId]!.transactionDateCreated != null) {
          transactionDateCreated = pendingTxMap[txId]!.transactionDateCreated!;
        } else {
          transactionDateCreated = dateCreatedCache[txId];
        }

        if (txConfirmed) {
          txStatus = TransactionStatus.confirmed;
        } else if (txNotFound) {
          final abovePendingThreshold = DateTime.now()
                  .difference(pendingTxMap[txId]!.dateCreated)
                  .inMinutes >
              kRequiredTxConfirmationPendingThreshold;

          if (abovePendingThreshold ||
              _isOverThePendingTime(transactionDateCreated)) {
            txStatus = TransactionStatus.failed;
          }
        }
        if (txStatus != null) {
          updates.add(
            NetworkTransactionsCompanion(
              transactionDateCreated: Value(transactionDateCreated),
              id: Value(txId),
              status: Value(txStatus),
            ),
          );
        }
      }
      if (updates.isNotEmpty) {
        await driveDao.insertNewNetworkTransactions(updates);
      }
      reportStep();
    }

    if (batchCount > 0) {
      onGatewayPhase?.call(false);
    }

    // Mark skipped transactions as confirmed
    if (txsIdsToSkip.isNotEmpty) {
      await driveDao.insertNewNetworkTransactions(
        txsIdsToSkip
            .map((txId) => NetworkTransactionsCompanion(
                  id: Value(txId),
                  status: const Value(TransactionStatus.confirmed),
                ))
            .toList(),
      );
    }
  }

  @override
  Future<void> createGhosts({
    required DriveDao driveDao,
    required Map<FolderID, GhostFolder> ghostFolders,
    String? ownerAddress,
    void Function(double fraction)? onProgress,
  }) async {
    final ghostFoldersByDrive =
        <DriveID, Map<FolderID, FolderEntriesCompanion>>{};

    // Collect all ghost folders to be created
    final ghostFoldersToCreate = <FolderEntry>[];

    if (ghostFolders.isEmpty) return;

    // Bulk pre-load existing folders and drives to avoid N+1 queries
    final existingFolderIds = (await driveDao
            .foldersByIds(folderIds: ghostFolders.keys.toList())
            .get())
        .map((f) => f.id)
        .toSet();
    final drivesMap = {
      for (final d in await driveDao.allDrives().get()) d.id: d
    };

    for (final ghostFolder in ghostFolders.values) {
      if (existingFolderIds.contains(ghostFolder.folderId)) {
        continue;
      }

      final drive = drivesMap[ghostFolder.driveId];
      if (drive == null) {
        continue;
      }

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
        var inserted = 0;
        for (final folderEntry in ghostFoldersToCreate) {
          await driveDao.into(driveDao.folderEntries).insert(folderEntry);
          // The same single transaction over the same rows in the same order.
          // The only new thing is that each row is reported as it lands.
          inserted++;
          onProgress?.call(inserted / ghostFoldersToCreate.length);
        }
      });
    }
  }

  @override
  Future<void> updateUserDrives({
    required Wallet wallet,
    required String password,
    required SecretKey cipherKey,
    bool forceRefresh = false,
    void Function(int read, int found)? onDriveRead,
  }) async {
    // Two callers that overlap share one fetch. A caller that arrives after
    // one has *finished* does not.
    //
    // It used to reuse a completed future as well, to spare a second query
    // when `syncMetadataOnly` and `startSync` ran seconds apart. That cache
    // hangs off this object, which `main.dart` provides above the auth gate,
    // so it outlives the session - while logging out drops every local table
    // (`deleteAllTables`). Logging back in then joined a fetch that had
    // already happened, wrote nothing into the emptied drive table, and left
    // the app stating as a fact that the user has no drives. Not only across
    // wallets: the same wallet in the same tab was enough, and nothing short
    // of a page reload recovered it.
    //
    // The full sync used to clear this on every login, which is what hid it
    // until the default stopped running one.
    if (!forceRefresh && _userDrivesUpdateFuture != null) {
      logger.d('Joining the drive-list fetch already in flight');
      return _userDrivesUpdateFuture!;
    }

    final future = _doUpdateUserDrives(
      wallet: wallet,
      password: password,
      cipherKey: cipherKey,
      onDriveRead: onDriveRead,
    );

    _userDrivesUpdateFuture = future;

    try {
      return await future;
    } finally {
      // Guarded on identity so a fetch that started while this one was
      // settling is not thrown away with it.
      if (identical(_userDrivesUpdateFuture, future)) {
        _userDrivesUpdateFuture = null;
      }
    }
  }

  Future<void> _doUpdateUserDrives({
    required Wallet wallet,
    required String password,
    required SecretKey cipherKey,
    void Function(int read, int found)? onDriveRead,
  }) async {
    // This syncs in the latest info on drives owned by the user and will be overwritten
    // below when the full sync process is ran.
    //
    // It also adds the encryption keys onto the drive models which isn't touched by the
    // later system.
    final userDriveEntities = await _arweave.getUniqueUserDriveEntities(
      wallet,
      password,
      onDriveRead: onDriveRead,
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

  int _transactionParseBatchSize(SyncProgress progress) =>
      SyncRepository.transactionParseBatchSizeFor(
        drivesCount: progress.drivesCount,
        drivesSynced: progress.drivesSynced,
      );

  int _calculateSyncLastBlockHeight(int lastBlockHeight) {
    logger.d('Calculating sync last block height: $lastBlockHeight');
    if (_lastSync != null) {
      return lastBlockHeight;
    } else {
      return max(lastBlockHeight - kBlockHeightLookBack, 0);
    }
  }

  /// Maps the data tx id of each pinned file to the address that actually owns
  /// it on-chain (the original uploader, not the drive owner). Used to resolve
  /// confirmation status for these cross-owner txs with a selective,
  /// owner-scoped query instead of an expensive unscoped one.
  Future<Map<String, String>> _buildPinnedDataTxOwnerOverrides(
    DriveDao driveDao,
  ) async {
    final pinnedFileRevisions = await driveDao.pinnedFileRevisions().get();
    return {
      for (final row in pinnedFileRevisions)
        if (row.pinnedDataOwnerAddress != null)
          row.dataTxId: row.pinnedDataOwnerAddress!,
    };
  }

  /// Maps each pending data tx id to the owner of the drive it belongs to, so
  /// the confirmation query can be scoped per-tx by the actual drive owner.
  /// This is needed because a single sync can span the user's own drives and
  /// attached drives owned by other wallets — assuming the logged-in wallet
  /// owns every pending tx would send an unscoped (or wrongly-scoped) query for
  /// the attached ones.
  Future<Map<String, String>> _buildPendingTxDriveOwners(
    DriveDao driveDao,
  ) async {
    final pendingRevisions = await driveDao.pendingDataFileRevisions().get();
    final ownerByDriveId = {
      for (final drive in await driveDao.allDrives().get())
        drive.id: drive.ownerAddress,
    };
    return {
      for (final revision in pendingRevisions)
        if ((ownerByDriveId[revision.driveId] ?? '').isNotEmpty)
          revision.dataTxId: ownerByDriveId[revision.driveId]!,
    };
  }

  Future<void> _updateTransactionStatuses({
    required DriveDao driveDao,
    required ArweaveService arweave,
    String? ownerAddress,
    List<TxID> txsIdsToSkip = const [],
    SyncCancellationToken? cancellationToken,

    /// Called as this phase's local database reads land, with the fraction of
    /// them done. Every one of them already happened; only the reporting is
    /// new.
    void Function(double fraction)? onLocalProgress,

    /// Called as the rest of the phase lands - the date pre-load chunks and
    /// each gateway confirmation batch - with the fraction of it done.
    /// Reporting only.
    void Function(double fraction)? onProgress,

    /// Called with true when the gateway confirmation loop begins and false
    /// when it is over. Nothing in here can measure that loop, so the bar is
    /// told to stop pretending to for its duration.
    void Function(bool active)? onGatewayPhase,
  }) async {
    // Check for cancellation at the start
    cancellationToken?.checkCancellation();

    // Three local database reads happen before the gateway is touched, and
    // were counted in nothing: the bar rested on the number the phase started
    // from until the gateway answered. A step each costs nothing - the reads
    // were already being made - and is the only granularity in this phase that
    // is real.
    const localReadCount = 3;
    var localReadsDone = 0;
    void reportLocalRead() {
      localReadsDone++;
      onLocalProgress?.call(localReadsDone / localReadCount);
    }

    final ownerOverrides = await _buildPinnedDataTxOwnerOverrides(driveDao);
    reportLocalRead();
    // Scope each pending tx by the owner of its own drive rather than assuming
    // the logged-in wallet owns everything (which is wrong for attached drives
    // owned by other wallets, and null when browsing without a wallet).
    final ownersByTxId = await _buildPendingTxDriveOwners(driveDao);
    reportLocalRead();

    // Load all pending transactions
    // Note: We load all at once here, but the memory impact is acceptable
    // since we're just building a map. The original code did the same.
    final allPendingTxs = await driveDao.pendingTransactions().get();
    reportLocalRead();

    logger.i('Loaded ${allPendingTxs.length} pending transactions');

    final pendingTxMap = <String, NetworkTransaction>{
      for (final tx in allPendingTxs) tx.id: tx,
    };

    /// Remove all confirmed transactions from the pending map
    /// and update the status of the remaining ones

    logger.i(
      'Skipping status update for ${txsIdsToSkip.length} transactions that were captured in snapshots',
    );

    for (final txId in txsIdsToSkip) {
      pendingTxMap.remove(txId);
    }

    // Bulk pre-load dateCreated for pending txs missing it (avoids N+1 queries)
    final txIdsNeedingDates = pendingTxMap.entries
        .where((e) => e.value.transactionDateCreated == null)
        .map((e) => e.key)
        .toList();

    // What is left of the phase after the local reads above, counted off the
    // work it already does: one step per date pre-load chunk, one per
    // confirmation batch. No extra query, and no invented ramp - a phase with
    // a single batch reports a single step, because a single step is what it
    // has. Finer detail than this lives inside the gateway call itself and
    // would mean changing ArweaveService, which is why the gateway stretch is
    // drawn as indeterminate rather than as a number.
    const page = 5000;
    final totalSteps = (txIdsNeedingDates.length / 500).ceil() +
        (pendingTxMap.length / page).ceil();
    var stepsDone = 0;
    void reportStep() {
      if (totalSteps == 0) return;
      stepsDone++;
      onProgress?.call(stepsDone / totalSteps);
    }

    final dateCreatedCache = <String, DateTime?>{};
    if (txIdsNeedingDates.isNotEmpty) {
      for (var i = 0; i < txIdsNeedingDates.length; i += 500) {
        final chunk = txIdsNeedingDates.sublist(
            i, min(i + 500, txIdsNeedingDates.length));
        final rows = await driveDao
            .fileRevisionDateCreatedByDataTxIds(txIds: chunk)
            .get();
        for (final row in rows) {
          dateCreatedCache[row.dataTxId] = row.dateCreated;
        }
        reportStep();
      }
    }

    final length = pendingTxMap.length;
    final list = pendingTxMap.keys.toList();

    // From here the phase belongs to the gateway, and how long it takes is
    // the gateway's to know. Rather than cross points of the bar on no
    // evidence, the bar goes indeterminate for the duration and picks the
    // number back up on the far side - however that side is reached.
    final batchCount = (length / page).ceil();
    if (batchCount > 0) {
      onGatewayPhase?.call(true);
    }

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

      // Caller-owned sink that getTransactionConfirmations populates with each
      // resolved confirmation. On timeout we fall back to it so the work done
      // before the deadline isn't discarded (it holds only verified
      // confirmations, so it never marks anything failed off a partial run).
      final verified = <String?, int>{};

      // Give each batch a generous timeout so a slow-but-successful response
      // can land instead of being discarded.
      final map = await arweave
          .getTransactionConfirmations(currentPage.toList(),
              owner: ownerAddress,
              ownersByTxId: ownersByTxId,
              ownerOverrides: ownerOverrides,
              verifiedSink: verified)
          .timeout(
        _txConfirmationBatchTimeout,
        onTimeout: () {
          logger.w('Individual transaction confirmation timeout; '
              'applying ${verified.length} confirmations resolved so far');
          return verified;
        },
      );

      map.forEach((key, value) {
        confirmations.putIfAbsent(key, () => value);
      });

      final updates = <NetworkTransactionsCompanion>[];
      for (final txId in currentPage) {
        // Check cancellation for each transaction
        cancellationToken?.checkCancellation();

        // Skip if confirmation data is missing (e.g., timeout or partial response)
        final confirmationCount = confirmations[txId];
        if (confirmationCount == null) {
          continue;
        }

        final txConfirmed = confirmationCount >= kRequiredTxConfirmationCount;
        final txNotFound = confirmationCount < 0;

        String? txStatus;

        DateTime? transactionDateCreated;

        if (pendingTxMap[txId]!.transactionDateCreated != null) {
          transactionDateCreated = pendingTxMap[txId]!.transactionDateCreated!;
        } else {
          transactionDateCreated = dateCreatedCache[txId];
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
          updates.add(
            NetworkTransactionsCompanion(
              transactionDateCreated: Value(transactionDateCreated),
              id: Value(txId),
              status: Value(txStatus),
            ),
          );
        }
      }
      if (updates.isNotEmpty) {
        await driveDao.insertNewNetworkTransactions(updates);
      }
      reportStep();
    }

    if (batchCount > 0) {
      onGatewayPhase?.call(false);
    }

    if (txsIdsToSkip.isNotEmpty) {
      await driveDao.insertNewNetworkTransactions(
        txsIdsToSkip
            .map((txId) => NetworkTransactionsCompanion(
                  id: Value(txId),
                  status: const Value(TransactionStatus.confirmed),
                ))
            .toList(),
      );
    }
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
    List<SnapshotEntityTransaction>? prefetchedSnapshots,
    bool skipPendingTxFetch = false,
    void Function()? onMetadataFetchProgress,
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

    final transactionBuffer = <DriveEntityHistoryTransactionModel>[];
    int totalTransactionsProcessed = 0;
    int totalTransactionsReceived = 0;

    List<SnapshotItem> snapshotItems = [];

    // Wrap snapshot processing in try/finally to ensure disposal
    try {
      if (_configService.config.enableSyncFromSnapshot) {
        // Use prefetched snapshots if available (batched query),
        // otherwise fall back to per-drive query
        final source = prefetchedSnapshots != null ? 'prefetched' : 'per-drive';
        final snapshotsStream = prefetchedSnapshots != null
            ? Stream.fromIterable(prefetchedSnapshots)
            : _arweave.getAllSnapshotsOfDrive(driveId, lastBlockHeight,
                ownerAddress: ownerAddress);

        snapshotItems = await SnapshotItem.instantiateAll(
          snapshotsStream,
          lastBlockHeight: lastBlockHeight,
          arweave: _arweave,
        ).toList();

        logger.i('[snapshot] $driveId: ${snapshotItems.length} usable '
            'from $source source (above block $lastBlockHeight)');

        final beforeValidation = snapshotItems.length;
        List<SnapshotItem> snapshotsVerified = await _snapshotValidationService
            .validateSnapshotItems(snapshotItems);

        if (snapshotsVerified.length != beforeValidation) {
          final rejected = snapshotItems
              .where((i) => !snapshotsVerified.contains(i))
              .map((i) => i.txId)
              .join(', ');
          logger.w('[snapshot] $driveId: '
              '${snapshotsVerified.length}/$beforeValidation available; '
              'unreachable: $rejected');
        } else if (beforeValidation > 0) {
          logger.i('[snapshot] $driveId: all $beforeValidation available');
        }

        snapshotItems = snapshotsVerified;
      } else {
        logger.i('[snapshot] $driveId: disabled by config '
            '(enableSyncFromSnapshot)');
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

      // The line that says whether this sync took the fast path. Blocks served
      // from a snapshot are read from one already-downloaded body; blocks left
      // to GraphQL are walked a page at a time, which for an old drive is
      // thousands of transactions and minutes of work. At info level
      // deliberately: when a sync is inexplicably slow, this is the first
      // thing worth seeing, and it is one line per drive.
      // `Range.end` is inclusive - `isInRange` tests `value <= end`, and
      // `union` treats `end + 1 == start` as contiguous - so the count has to
      // include both endpoints. Without the +1 a single-block range reports
      // zero, which is the one number this line must never print wrongly.
      int blocksIn(HeightRange r) =>
          r.rangeSegments.fold(0, (sum, s) => sum + (s.end - s.start + 1));

      final fromSnapshots = blocksIn(snapshotDriveHistory.subRanges);
      final fromGql = blocksIn(gqlDriveHistorySubRanges);

      if (snapshotItems.isEmpty) {
        logger.i('[snapshot] $driveId: none usable - walking all $fromGql '
            'blocks over GraphQL');
      } else {
        logger.i('[snapshot] $driveId: $fromSnapshots blocks from '
            '${snapshotItems.length} snapshot(s), $fromGql over GraphQL');
      }

      logger.d(
          'Total range to query for: ${totalRangeToQueryFor.rangeSegments}\n'
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

      /// Streaming phase: fetch and parse in chunks to reduce memory usage
      await for (DriveEntityHistoryTransactionModel t in transactionsStream) {
        // Check for cancellation periodically
        token.checkCancellation();

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

        // Add transaction to buffer
        transactionBuffer.add(t);
        totalTransactionsReceived++;

        // Process chunk when buffer is full
        if (transactionBuffer.length >= kStreamTransactionChunkSize) {
          await _processTransactionChunk(
            transactions: List.from(transactionBuffer),
            drive: drive,
            driveKey: driveKey?.key,
            currentBlockHeight: currentBlockHeight,
            lastBlockHeight: lastBlockHeight,
            transactionParseBatchSize: transactionParseBatchSize,
            snapshotDriveHistory: snapshotDriveHistory,
            ownerAddress: ownerAddress,
            onMetadataFetchProgress: onMetadataFetchProgress,
          );

          totalTransactionsProcessed += transactionBuffer.length;
          transactionBuffer.clear();

          logger.d(
              'Processed $totalTransactionsProcessed / $totalTransactionsReceived transactions');
        }

        // Calculate and yield progress based on block heights
        if (firstBlockHeight != null && totalBlockHeightDifference > 0) {
          final block = t.transactionCommonMixin.block;
          if (block != null) {
            fetchPhasePercentage = 1 -
                ((currentBlockHeight - block.height) /
                    totalBlockHeightDifference);
          }

          // Yield progress (80% for streaming, 20% reserved for final operations)
          final streamProgress = fetchPhasePercentage * 0.8;
          yield streamProgress;
        }
      }

      // Process remaining transactions in buffer
      if (transactionBuffer.isNotEmpty) {
        logger.d(
            'Processing final chunk of ${transactionBuffer.length} transactions');

        try {
          await _processTransactionChunk(
            transactions: transactionBuffer,
            drive: drive,
            driveKey: driveKey?.key,
            currentBlockHeight: currentBlockHeight,
            lastBlockHeight: lastBlockHeight,
            transactionParseBatchSize: transactionParseBatchSize,
            snapshotDriveHistory: snapshotDriveHistory,
            ownerAddress: ownerAddress,
            onMetadataFetchProgress: onMetadataFetchProgress,
          );

          totalTransactionsProcessed += transactionBuffer.length;
          transactionBuffer.clear();
        } catch (e) {
          logger.e(
              '[Sync Drive] Error while parsing final transaction chunk', e);
          rethrow;
        }
      }

      logger.d(
          'Done processing all $totalTransactionsProcessed transactions - ${gqlDriveHistory.driveId}');

      txFechedCallback?.call(drive.id, gqlDriveHistory.txCount);

      final fetchPhaseTotalTime =
          DateTime.now().difference(fetchPhaseStartDT).inMilliseconds;

      logger.d(
          'Duration of streaming phase for ${drive.name}: $fetchPhaseTotalTime ms. Processed $totalTransactionsProcessed transactions');

      // Fetch pending (unmined) transactions to show Turbo uploads immediately.
      // This is best-effort: errors here should not fail the drive sync.
      // Skip for non-owned drives (can't have this user's pending uploads)
      // and when no locally-tracked pending transactions exist for this drive.
      int pendingTransactionCount = 0;

      if (skipPendingTxFetch) {
        logger.d(
            'Skipping pending tx fetch for drive ${drive.id} (not owned by user)');
      } else {
        // Check local DB first: only query the gateway if we have
        // locally-tracked pending transactions for this drive
        final localPending =
            await _driveDao.pendingTransactionsForDrive(driveId: driveId).get();

        if (localPending.isEmpty) {
          logger.d(
              'No locally pending transactions for drive ${drive.id}, skipping GQL query');
        } else {
          logger.d('Fetching pending transactions for drive ${drive.id} '
              '(${localPending.length} locally pending)');

          try {
            await for (final pendingTxBatch
                in _arweave.getPendingTransactionsForDrive(
              driveId,
              ownerAddress: ownerAddress,
            )) {
              // Check for cancellation before processing each batch
              if (token.isCancelled) {
                logger.d(
                    'Pending transactions fetch cancelled for drive ${drive.id}');
                break;
              }

              if (pendingTxBatch.isNotEmpty) {
                logger.d(
                    'Processing ${pendingTxBatch.length} pending transactions');

                await _processTransactionChunk(
                  transactions: pendingTxBatch,
                  drive: drive,
                  driveKey: driveKey?.key,
                  currentBlockHeight: currentBlockHeight,
                  lastBlockHeight: lastBlockHeight,
                  transactionParseBatchSize: transactionParseBatchSize,
                  snapshotDriveHistory: snapshotDriveHistory,
                  ownerAddress: ownerAddress,
                );

                pendingTransactionCount += pendingTxBatch.length;
              }
            }
          } catch (e) {
            // Log but don't rethrow - pending tx fetch is best-effort
            logger.w(
                'Error fetching pending transactions for drive ${drive.id}: $e');
          }

          if (pendingTransactionCount > 0) {
            logger.i(
                'Processed $pendingTransactionCount pending transactions for drive ${drive.name}');
          }
        }
      }

      // Yield final progress before cleanup
      yield 0.8;

      final syncDriveTotalTime =
          DateTime.now().difference(startSyncDT).inMilliseconds;

      final averageBetweenFetchAndGet =
          fetchPhaseTotalTime / syncDriveTotalTime;

      logger.i(
          'Drive ${drive.name} completed parse phase. Progress by block height: $fetchPhasePercentage%. Starting parse phase. Sync duration: $syncDriveTotalTime ms. Fetching used ${(averageBetweenFetchAndGet * 100).toStringAsFixed(2)}% of drive sync process');
    } finally {
      // Where this drive's entity metadata actually came from. A snapshot
      // that covers a range but serves none of its metadata is indis-
      // tinguishable, from the outside, from one that is working - both look
      // like "3 snapshots loaded" followed by a long sync. This is the line
      // that tells them apart.
      //
      // Drained here rather than at the end of the happy path, for the same
      // reason the cache below is: a sync that throws or is cancelled would
      // otherwise leave its counts behind, and they are keyed by drive - so
      // the next sync of that drive would add to them and report a total that
      // never happened. Cancelling mid-sync is a normal thing to do.
      final hits = _arweave.snapshotMetadataHits.remove(drive.id) ?? 0;
      final misses = _arweave.snapshotMetadataMisses.remove(drive.id) ?? 0;
      if (hits + misses > 0) {
        logger.i('[snapshot] ${drive.id}: $hits entity metadata read(s) from '
            'snapshots, $misses fetched from the gateway');
      }

      // Always dispose snapshot cache, even on error or cancellation
      await SnapshotItemOnChain.dispose(drive.id);
      logger.d('Disposed snapshot cache for drive ${drive.id}');
    }
  }

  /// Process a chunk of transactions through the entity parsing pipeline.
  /// This helper method is used by streaming sync to process transactions in batches.
  Future<void> _processTransactionChunk({
    required List<DriveEntityHistoryTransactionModel> transactions,
    required Drive drive,
    required SecretKey? driveKey,
    required int currentBlockHeight,
    required int lastBlockHeight,
    required int transactionParseBatchSize,
    required SnapshotDriveHistory snapshotDriveHistory,
    required String ownerAddress,
    void Function()? onMetadataFetchProgress,
  }) async {
    if (transactions.isEmpty) return;

    logger.d('Processing chunk of ${transactions.length} transactions');

    // What this chunk will ask for, announced before it asks for any of it.
    //
    // The total used to grow one batch at a time, from inside the batch loop -
    // and every batch's fetches finished before the next batch was scheduled,
    // so the two numbers met at every boundary and the only value that ever
    // sat on screen long enough to read was "N of N". A denominator that is
    // always the numerator tells the reader nothing.
    //
    // This is still a figure the sync actually has rather than a guess at the
    // drive's size: it is the length of the history chunk in hand.
    _metadataFetchesScheduled += transactions.length;
    onMetadataFetchProgress?.call();

    await for (final _ in _parseDriveTransactionsIntoDatabaseEntities(
      transactions: transactions,
      drive: drive,
      driveKey: driveKey,
      currentBlockHeight: currentBlockHeight,
      lastBlockHeight: lastBlockHeight,
      batchSize: transactionParseBatchSize,
      snapshotDriveHistory: snapshotDriveHistory,
      ownerAddress: ownerAddress,
      onMetadataFetchProgress: onMetadataFetchProgress,
    )) {
      // Just consume the stream, progress is handled in main loop
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

    /// Called whenever [_metadataFetchesScheduled] or
    /// [_metadataFetchesCompleted] moves, so the sync can republish them.
    ///
    /// Threaded down rather than read off a field the repository sets, because
    /// only the sync that is running owns the sink these numbers go out on -
    /// and `syncDriveById` walks a drive with no sink at all.
    void Function()? onMetadataFetchProgress,
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

    // Pre-load all latest/oldest revisions for this drive into maps.
    // Replaces thousands of individual DB queries with 4 bulk queries.
    final isFirstSync =
        drive.lastBlockHeight == null || drive.lastBlockHeight == 0;

    final latestFileRevisionsCache = isFirstSync
        ? <String, FileRevisionsCompanion>{}
        : <String, FileRevisionsCompanion>{
            for (final e
                in (await _driveDao.getAllLatestFileRevisionsMap(drive.id))
                    .entries)
              e.key: e.value.toCompanion(true),
          };

    final latestFolderRevisionsCache = isFirstSync
        ? <String, FolderRevisionsCompanion>{}
        : <String, FolderRevisionsCompanion>{
            for (final e
                in (await _driveDao.getAllLatestFolderRevisionsMap(drive.id))
                    .entries)
              e.key: e.value.toCompanion(true),
          };

    // Oldest revision maps — immutable during processing since inserting
    // newer revisions doesn't change the oldest.
    final oldestFileRevisionsCache = isFirstSync
        ? <String, FileRevision>{}
        : await _driveDao.getAllOldestFileRevisionsMap(drive.id);

    final oldestFolderRevisionsCache = isFirstSync
        ? <String, FolderRevision>{}
        : await _driveDao.getAllOldestFolderRevisionsMap(drive.id);

    if (!isFirstSync) {
      logger.d('Pre-loaded revision caches: '
          '${latestFileRevisionsCache.length} files, '
          '${latestFolderRevisionsCache.length} folders');
    }

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
            currentBlockHeight: currentBlockHeight,
            // The count of what is *done*, as each one finishes - not what has
            // been started, and not one step per batch. This is the whole of
            // what moves during the phase; everything else the sync publishes
            // is frozen until the batch is over.
            onEntityFetched: () {
              _metadataFetchesCompleted++;
              onMetadataFetchProgress?.call();
            },
          );

          _recordSkippedEntities(drive.id, entityHistory.skippedTxIds);

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

          // The tally only counts what committed - see
          // [_pendingSyncedEntityIdsByDrive].
          var committed = false;
          try {
          await _driveDao.runTransaction(() async {
            final latestDriveRevision = await _addNewDriveEntityRevisions(
              newEntities: newEntities.whereType<DriveEntity>(),
            );
            final latestFolderRevisions = await _addNewFolderEntityRevisions(
              driveId: drive.id,
              newEntities: newEntities.whereType<FolderEntity>(),
              latestRevisionsCache: latestFolderRevisionsCache,
            );
            final latestFileRevisions = await _addNewFileEntityRevisions(
              driveId: drive.id,
              newEntities: newEntities.whereType<FileEntity>(),
              latestRevisionsCache: latestFileRevisionsCache,
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
              oldestRevisionsCache: oldestFolderRevisionsCache,
            );
            final updatedFilesById =
                await _computeRefreshedFileEntriesFromRevisions(
              driveDao: _driveDao,
              driveId: drive.id,
              revisionsByFileId: latestFileRevisions,
              oldestRevisionsCache: oldestFileRevisionsCache,
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
            committed = true;
          } finally {
            if (committed) {
              _commitSyncedEntities();
            } else {
              _discardPendingSyncedEntities();
            }
          }
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
    required Map<String, FileRevisionsCompanion> latestRevisionsCache,
  }) async {
    // The latest file revisions, keyed by their entity ids.
    final latestRevisions = <String, FileRevisionsCompanion>{};

    final newRevisions = <FileRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id) &&
          entity.parentFolderId != null) {
        // Use pre-loaded cache instead of per-entity DB query
        final cached = latestRevisionsCache[entity.id!];
        if (cached != null) {
          latestRevisions[entity.id!] = cached;
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
            latestRevisionsCache[entity.id!] = revision;
            newRevisions.add(revision);
          }
        } else {
          latestRevisions[entity.id!] = revision;
          latestRevisionsCache[entity.id!] = revision;
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

    _recordSyncedEntities(driveId, newRevisions.map((r) => r.fileId.value));

    return latestRevisions.values.toList();
  }

  /// Computes the new folder revisions from the provided entities, inserts them into the database,
  /// and returns only the latest revisions.
  Future<List<FolderRevisionsCompanion>> _addNewFolderEntityRevisions({
    required String driveId,
    required Iterable<FolderEntity> newEntities,
    required Map<String, FolderRevisionsCompanion> latestRevisionsCache,
  }) async {
    _folderIds.addAll(newEntities.map((e) => e.id!));
    // The latest folder revisions, keyed by their entity ids.
    final latestRevisions = <String, FolderRevisionsCompanion>{};

    final newRevisions = <FolderRevisionsCompanion>[];
    for (final entity in newEntities) {
      if (!latestRevisions.containsKey(entity.id)) {
        // Use pre-loaded cache instead of per-entity DB query
        final cached = latestRevisionsCache[entity.id!];
        if (cached != null) {
          latestRevisions[entity.id!] = cached;
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
      latestRevisionsCache[entity.id!] = revision;
    }
    final newNetworkTransactions =
        createNetworkTransactionsCompanionsForFolders(
      newRevisions,
    );
    await _driveDao.insertNewFolderRevisions(newRevisions);
    await _driveDao.insertNewNetworkTransactions(newNetworkTransactions);

    _recordSyncedEntities(driveId, newRevisions.map((r) => r.folderId.value));

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

  @override
  @override
  Future<bool> hasPendingTransactions() {
    return _driveDao.hasPendingTransactions();
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
  required Map<String, FileRevision> oldestRevisionsCache,
}) async {
  // Build map of entry companions AND keep revision dateCreated for fallback
  final revisionDateByFileId = <String, DateTime>{};
  final updatedFilesById = <String, FileEntriesCompanion>{};
  for (final revision in revisionsByFileId) {
    final fileId = revision.fileId.value;
    updatedFilesById[fileId] = revision.toEntryCompanion();
    revisionDateByFileId[fileId] = revision.dateCreated.value;
  }

  for (final fileId in updatedFilesById.keys) {
    // Use pre-loaded cache instead of per-entity DB query.
    // Fall back to the revision's own dateCreated (not the entry companion's,
    // which may be Value.absent due to schema defaults).
    final oldestRevision = oldestRevisionsCache[fileId];
    final dateCreated =
        oldestRevision?.dateCreated ?? revisionDateByFileId[fileId]!;

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
  required Map<String, FolderRevision> oldestRevisionsCache,
}) async {
  // Build map of entry companions AND keep revision dateCreated for fallback
  final revisionDateByFolderId = <String, DateTime>{};
  final updatedFoldersById = <String, FolderEntriesCompanion>{};
  for (final revision in revisionsByFolderId) {
    final folderId = revision.folderId.value;
    updatedFoldersById[folderId] = revision.toEntryCompanion();
    revisionDateByFolderId[folderId] = revision.dateCreated.value;
  }

  for (final folderId in updatedFoldersById.keys) {
    // Use pre-loaded cache instead of per-entity DB query.
    // Fall back to the revision's own dateCreated (not the entry companion's,
    // which may be Value.absent due to schema defaults).
    final oldestRevision = oldestRevisionsCache[folderId];
    final dateCreated =
        oldestRevision?.dateCreated ?? revisionDateByFolderId[folderId]!;

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
          oldestRevision?.dateCreated ?? latestRevision.dateCreated.value,
        ),
      );
}
