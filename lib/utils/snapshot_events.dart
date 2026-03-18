import 'dart:async';

import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';

/// Event emitted when a new snapshot is created.
///
/// Used for optimistic updates in the UI before the snapshot
/// is confirmed on the blockchain.
class SnapshotCreatedEvent {
  final SnapshotDisplayItem snapshot;
  final DateTime timestamp;

  SnapshotCreatedEvent(this.snapshot) : timestamp = DateTime.now();
}

/// Event bus for snapshot-related events.
///
/// This singleton allows the [CreateSnapshotCubit] to notify
/// [FsEntrySnapshotsCubit] instances when a new snapshot is created,
/// enabling optimistic UI updates.
///
/// Since Flutter's TabBarView lazily builds tabs, the [FsEntrySnapshotsCubit]
/// may not exist when a snapshot is created. This bus stores recent pending
/// snapshots and replays them to new subscribers.
class SnapshotEventBus {
  SnapshotEventBus._();

  static final SnapshotEventBus _instance = SnapshotEventBus._();
  static SnapshotEventBus get instance => _instance;

  final StreamController<SnapshotCreatedEvent> _controller =
      StreamController<SnapshotCreatedEvent>.broadcast();

  /// Stores recent pending snapshots for replay to new subscribers.
  /// Key is driveId, value is the most recent pending snapshot for that drive.
  final Map<String, SnapshotCreatedEvent> _pendingSnapshots = {};

  /// How long to keep pending snapshots for replay (10 minutes).
  static const Duration _pendingRetention = Duration(minutes: 10);

  /// Stream of snapshot created events.
  Stream<SnapshotCreatedEvent> get stream => _controller.stream;

  /// Gets any pending snapshots for a specific drive that should be replayed.
  /// Returns null if no pending snapshot exists or if it's too old.
  SnapshotDisplayItem? getPendingSnapshot(String driveId) {
    final event = _pendingSnapshots[driveId];
    if (event == null) return null;

    // Check if the pending snapshot is still fresh
    if (DateTime.now().difference(event.timestamp) > _pendingRetention) {
      _pendingSnapshots.remove(driveId);
      return null;
    }

    return event.snapshot;
  }

  /// Marks a pending snapshot as consumed (e.g., when it's been added to the list).
  void consumePendingSnapshot(String driveId, String txId) {
    final event = _pendingSnapshots[driveId];
    if (event != null && event.snapshot.txId == txId) {
      _pendingSnapshots.remove(driveId);
    }
  }

  /// Emits a snapshot created event to all listeners.
  void emitSnapshotCreated(SnapshotDisplayItem snapshot) {
    // Store for replay to late subscribers (TabBarView lazy loading)
    final event = SnapshotCreatedEvent(snapshot);
    _pendingSnapshots[snapshot.driveId] = event;

    _controller.add(event);
  }

  /// Disposes the event bus. Should only be called when the app shuts down.
  void dispose() {
    _controller.close();
    _pendingSnapshots.clear();
  }
}
