import 'package:ardrive/blocs/fs_entry_snapshots/models/snapshot_display_item.dart';

/// Simple in-memory cache for drive snapshots.
///
/// Caches snapshot data per drive to avoid repeated GraphQL queries
/// when switching tabs or re-selecting a drive.
class SnapshotsCache {
  SnapshotsCache._();

  static final SnapshotsCache _instance = SnapshotsCache._();
  static SnapshotsCache get instance => _instance;

  /// Cache of snapshots per drive ID.
  final Map<String, _CacheEntry> _cache = {};

  /// How long cached data is considered fresh (5 minutes).
  static const Duration _cacheDuration = Duration(minutes: 5);

  /// Gets cached snapshots for a drive if available and not stale.
  List<SnapshotDisplayItem>? get(String driveId) {
    final entry = _cache[driveId];
    if (entry == null) return null;

    // Check if cache is stale
    if (DateTime.now().difference(entry.timestamp) > _cacheDuration) {
      _cache.remove(driveId);
      return null;
    }

    return entry.snapshots;
  }

  /// Caches snapshots for a drive.
  void set(String driveId, List<SnapshotDisplayItem> snapshots) {
    _cache[driveId] = _CacheEntry(
      snapshots: snapshots,
      timestamp: DateTime.now(),
    );
  }

  /// Adds a pending snapshot to the cache for a drive.
  void addPending(String driveId, SnapshotDisplayItem snapshot) {
    final entry = _cache[driveId];
    if (entry == null) return;

    // Check if already exists
    if (entry.snapshots.any((s) => s.txId == snapshot.txId)) return;

    // Add to beginning of list
    _cache[driveId] = _CacheEntry(
      snapshots: [snapshot, ...entry.snapshots],
      timestamp: entry.timestamp,
    );
  }

  /// Invalidates cache for a specific drive.
  void invalidate(String driveId) {
    _cache.remove(driveId);
  }

  /// Clears entire cache.
  void clear() {
    _cache.clear();
  }
}

class _CacheEntry {
  final List<SnapshotDisplayItem> snapshots;
  final DateTime timestamp;

  _CacheEntry({
    required this.snapshots,
    required this.timestamp,
  });
}
