import 'dart:async';

import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';
import 'package:ardrive/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshot_events.dart';
import 'package:ardrive/utils/snapshots/snapshot_item.dart';
import 'package:ardrive/utils/snapshots/snapshots_cache.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'fs_entry_snapshots_state.dart';

/// Cubit that manages the list of snapshots for a drive.
///
/// Fetches snapshots from Arweave and listens to [SnapshotEventBus]
/// for optimistic updates when new snapshots are created.
class FsEntrySnapshotsCubit extends Cubit<FsEntrySnapshotsState> {
  final String driveId;
  final String ownerAddress;
  final ArweaveService _arweaveService;

  StreamSubscription<SnapshotCreatedEvent>? _eventBusSubscription;
  List<SnapshotDisplayItem> _snapshots = [];

  FsEntrySnapshotsCubit({
    required this.driveId,
    required this.ownerAddress,
    required ArweaveService arweaveService,
  })  : _arweaveService = arweaveService,
        super(FsEntrySnapshotsInitial()) {
    _init();
  }

  void _init() {
    _loadSnapshots();
    _subscribeToEventBus();
    _checkForMissedPendingSnapshots();
  }

  void _subscribeToEventBus() {
    _eventBusSubscription = SnapshotEventBus.instance.stream.listen((event) {
      // Only add snapshots for this drive
      if (event.snapshot.driveId == driveId) {
        _addPendingSnapshot(event.snapshot);
      }
    });
  }

  /// Checks for any pending snapshots that were created before this cubit existed.
  /// This handles the case where TabBarView lazily builds tabs.
  void _checkForMissedPendingSnapshots() {
    final pendingSnapshot =
        SnapshotEventBus.instance.getPendingSnapshot(driveId);
    if (pendingSnapshot != null) {
      _addPendingSnapshot(pendingSnapshot);
      // Mark as consumed so it's not replayed again
      SnapshotEventBus.instance
          .consumePendingSnapshot(driveId, pendingSnapshot.txId);
    }
  }

  /// Checks if the drive would benefit from a snapshot.
  /// Uses the same threshold (1000 transactions) as PromptToSnapshotBloc.
  bool _shouldRecommendSnapshot() {
    return CountOfTxsSyncedWithGql.wouldDriveBenefitFromSnapshot(
      driveId,
      defaultNumberOfTxsBeforeSnapshot,
    );
  }

  void _addPendingSnapshot(SnapshotDisplayItem snapshot) {
    if (isClosed) return;

    // Check if this snapshot already exists (by txId)
    final existingIndex = _snapshots.indexWhere((s) => s.txId == snapshot.txId);
    if (existingIndex >= 0) {
      return; // Already exists, don't add duplicate
    }

    // Add to the beginning of the list (most recent first)
    _snapshots = [snapshot, ..._snapshots];

    // Update cache
    SnapshotsCache.instance.addPending(driveId, snapshot);

    emit(FsEntrySnapshotsSuccess(
      snapshots: List.unmodifiable(_snapshots),
      shouldRecommendSnapshot: _shouldRecommendSnapshot(),
    ));
  }

  Future<void> _loadSnapshots({bool forceRefresh = false}) async {
    if (isClosed) return;

    // Check cache first (unless force refresh)
    if (!forceRefresh) {
      final cached = SnapshotsCache.instance.get(driveId);
      if (cached != null) {
        _snapshots = List.from(cached);
        emit(FsEntrySnapshotsSuccess(
          snapshots: List.unmodifiable(_snapshots),
          shouldRecommendSnapshot: _shouldRecommendSnapshot(),
        ));
        return;
      }
    }

    emit(FsEntrySnapshotsLoading());

    try {
      final snapshots = <SnapshotDisplayItem>[];

      await for (final snapshotTx in _arweaveService.getAllSnapshotsOfDrive(
        driveId,
        null, // lastBlockHeight - we want all snapshots
        ownerAddress: ownerAddress,
      )) {
        try {
          // Parse block start and end from tags
          final tags = snapshotTx.tags;
          final blockStartTag = tags.firstWhere(
            (t) => t.name == 'Block-Start',
            orElse: () => throw MalformedSnapshotException(
              txId: snapshotTx.id,
              reason: 'Missing Block-Start tag',
            ),
          );
          final blockEndTag = tags.firstWhere(
            (t) => t.name == 'Block-End',
            orElse: () => throw MalformedSnapshotException(
              txId: snapshotTx.id,
              reason: 'Missing Block-End tag',
            ),
          );

          final blockStart = int.parse(blockStartTag.value);
          final blockEnd = int.parse(blockEndTag.value);

          // Get timestamp from block
          final timestamp = snapshotTx.block?.timestamp;
          final createdAt = timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(timestamp * 1000)
              : DateTime.now();

          // Snapshots from GraphQL are confirmed (they have a block height)
          snapshots.add(SnapshotDisplayItem(
            txId: snapshotTx.id,
            driveId: driveId,
            blockStart: blockStart,
            blockEnd: blockEnd,
            createdAt: createdAt,
            // status defaults to TransactionStatus.confirmed
          ));
        } on MalformedSnapshotException catch (e) {
          logger.w('Skipping malformed snapshot: $e');
          continue;
        } catch (e) {
          logger.w('Error parsing snapshot ${snapshotTx.id}: $e');
          continue;
        }
      }

      // Sort by createdAt descending (most recent first)
      snapshots.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      // Get confirmed txIds for deduplication
      final confirmedTxIds = snapshots.map((s) => s.txId).toSet();

      // Keep pending snapshots that haven't been confirmed yet
      final pendingSnapshots = _snapshots
          .where((s) => s.isPending && !confirmedTxIds.contains(s.txId))
          .toList();

      _snapshots = [...pendingSnapshots, ...snapshots];

      // Update cache
      SnapshotsCache.instance.set(driveId, _snapshots);

      if (isClosed) return;
      emit(FsEntrySnapshotsSuccess(
        snapshots: List.unmodifiable(_snapshots),
        shouldRecommendSnapshot: _shouldRecommendSnapshot(),
      ));
    } catch (e, stackTrace) {
      logger.e('Failed to load snapshots for drive $driveId', e, stackTrace);
      if (isClosed) return;
      emit(FsEntrySnapshotsFailure(errorMessage: e.toString()));
    }
  }

  /// Refreshes the list of snapshots from Arweave, bypassing cache.
  Future<void> refresh() async {
    await _loadSnapshots(forceRefresh: true);
  }

  @override
  Future<void> close() {
    _eventBusSubscription?.cancel();
    return super.close();
  }
}
