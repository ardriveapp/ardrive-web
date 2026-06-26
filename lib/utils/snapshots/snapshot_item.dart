import 'dart:async';
import 'dart:convert';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:stash/stash_api.dart';
import 'package:stash_memory/stash_memory.dart';

// TODO: PE-2782: Abstract auto-generated GQL types
typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;
typedef SnapshotEntityTransaction
    = SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

/// Exception thrown when a snapshot transaction is missing required tags
/// or has invalid data that prevents it from being processed.
class MalformedSnapshotException implements Exception {
  final String txId;
  final String reason;

  MalformedSnapshotException({
    required this.txId,
    required this.reason,
  });

  @override
  String toString() =>
      'MalformedSnapshotException: Snapshot $txId is malformed: $reason';
}

abstract class SnapshotItem implements SegmentedGQLData {
  abstract final int blockStart;
  abstract final int blockEnd;
  abstract final DriveID driveId;
  abstract final String txId;

  factory SnapshotItem.fromGQLNode({
    required SnapshotEntityTransaction node,
    required HeightRange subRanges,
    required ArweaveService arweave,
    @visibleForTesting String? fakeSource,
  }) {
    final tags = node.tags;
    final blockStart = tags.firstWhere(
      (element) => element.name == 'Block-Start',
      orElse: () => throw MalformedSnapshotException(
        txId: node.id,
        reason: 'Missing required tag: Block-Start',
      ),
    ).value;
    final blockEnd = tags.firstWhere(
      (element) => element.name == 'Block-End',
      orElse: () => throw MalformedSnapshotException(
        txId: node.id,
        reason: 'Missing required tag: Block-End',
      ),
    ).value;
    final driveId = tags.firstWhere(
      (element) => element.name == 'Drive-Id',
      orElse: () => throw MalformedSnapshotException(
        txId: node.id,
        reason: 'Missing required tag: Drive-Id',
      ),
    ).value;
    final timestamp = node.block!.timestamp;
    final txId = node.id;

    return SnapshotItemOnChain(
      blockStart: int.parse(blockStart),
      blockEnd: int.parse(blockEnd),
      driveId: driveId,
      timestamp: timestamp,
      txId: txId,
      subRanges: subRanges,
      arweave: arweave,
      fakeSource: fakeSource,
    );
  }

  /// itemStream - The result of SnapshotEntityHistory query in DESC order (newer first)
  static Stream<SnapshotItem> instantiateAll(
    Stream<SnapshotEntityTransaction> itemsStream, {
    int? lastBlockHeight,
    required ArweaveService arweave,
    @visibleForTesting String? fakeSource,
  }) async* {
    HeightRange obscuredByAccumulator = HeightRange(rangeSegments: [
      if (lastBlockHeight != null) Range(start: 0, end: lastBlockHeight),
    ]);

    await for (SnapshotEntityTransaction item in itemsStream) {
      late SnapshotItem snapshotItem;

      try {
        snapshotItem = instantiateSingle(
          item,
          obscuredBy: obscuredByAccumulator,
          fakeSource: fakeSource,
          arweave: arweave,
        );
      } catch (e) {
        if (e is MalformedSnapshotException) {
          logger.w('Skipping malformed snapshot: $e');
        } else {
          logger.e('Ignoring snapshot transaction with invalid block range', e);
        }
        continue;
      }

      yield snapshotItem;

      Range totalSnapshotRange =
          Range(start: snapshotItem.blockStart, end: snapshotItem.blockEnd);
      HeightRange totalHeightRange =
          HeightRange(rangeSegments: [totalSnapshotRange]);
      obscuredByAccumulator = HeightRange.union(
        obscuredByAccumulator,
        totalHeightRange,
      );
    }
  }

  static SnapshotItem instantiateSingle(
    SnapshotEntityTransaction item, {
    required HeightRange obscuredBy,
    required ArweaveService arweave,
    @visibleForTesting String? fakeSource,
  }) {
    late Range totalRange;
    List<TransactionCommonMixin$Tag> tags = item.tags;
    String? maybeBlockHeightStart = tags.firstWhere(
      (tag) => tag.name == 'Block-Start',
      orElse: () => throw MalformedSnapshotException(
        txId: item.id,
        reason: 'Missing required tag: Block-Start',
      ),
    ).value;
    String? maybeBlockHeightEnd = tags.firstWhere(
      (tag) => tag.name == 'Block-End',
      orElse: () => throw MalformedSnapshotException(
        txId: item.id,
        reason: 'Missing required tag: Block-End',
      ),
    ).value;

    try {
      int blockHeightStart = int.parse(maybeBlockHeightStart);
      int blockHeightEnd = int.parse(maybeBlockHeightEnd);
      totalRange = Range(start: blockHeightStart, end: blockHeightEnd);
    } catch (_) {
      throw BadRange(start: maybeBlockHeightStart, end: maybeBlockHeightEnd);
    }

    HeightRange totalHeightRange = HeightRange(rangeSegments: [totalRange]);
    HeightRange subRanges = HeightRange.difference(
      totalHeightRange,
      obscuredBy,
    );
    SnapshotItem snapshotItem = SnapshotItem.fromGQLNode(
      node: item,
      subRanges: subRanges,
      arweave: arweave,
      fakeSource: fakeSource,
    );
    return snapshotItem;
  }

  @override
  String toString() {
    return 'SnapshotItem{blockStart: $blockStart, blockEnd: $blockEnd, driveId: $driveId, subRanges: $subRanges}';
  }
}

class SnapshotItemOnChain implements SnapshotItem {
  final int timestamp;

  @override
  final TxID txId;
  String? _cachedSource;
  int _currentIndex = -1;

  final ArweaveService _arweave;

  static final Map<String, Cache<Uint8List>> _jsonMetadataCaches = {};
  static final Map<String, Future<Cache<Uint8List>>> _cacheInitFutures = {};
  static final Map<DriveID, Set<TxID>> _txIdsByDrive = {};

  SnapshotItemOnChain({
    required this.blockEnd,
    required this.blockStart,
    required this.driveId,
    required this.timestamp,
    required this.txId,
    required this.subRanges,
    required ArweaveService arweave,
    @visibleForTesting String? fakeSource,
  })  : _cachedSource = fakeSource,
        _arweave = arweave;

  @override
  final HeightRange subRanges;
  @override
  final int blockStart;
  @override
  final int blockEnd;
  @override
  final DriveID driveId;
  @override
  int get currentIndex => _currentIndex;

  Future<String>? _prefetchFuture;

  Future<String> _source() async {
    if (_cachedSource != null) {
      return _cachedSource!;
    }
    // Use prefetch result if available, otherwise fetch now
    if (_prefetchFuture != null) {
      return _cachedSource = await _prefetchFuture!;
    }
    final dataBytes = await _arweave.getEntityDataFromNetwork(txId: txId);
    final dataBytesAsString = String.fromCharCodes(dataBytes);
    return _cachedSource = dataBytesAsString;
  }

  /// Start downloading the snapshot body without waiting for it.
  /// Call this on the NEXT snapshot while processing the current one.
  void prefetch() {
    if (_cachedSource != null || _prefetchFuture != null) return;
    logger.d('Prefetching snapshot $txId');
    _prefetchFuture = _arweave
        .getEntityDataFromNetwork(txId: txId)
        .then((bytes) => String.fromCharCodes(bytes));
  }

  @override
  Stream<DriveEntityHistoryTransactionModel> getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  /// Parses snapshot entries one at a time by scanning for object boundaries
  /// in the JSON string, avoiding a full jsonDecode of the entire snapshot.
  /// This keeps memory bounded to one entry at a time instead of the full Map.
  Stream<DriveEntityHistoryTransactionModel> _getNextStream() async* {
    final Range range = subRanges.rangeSegments[currentIndex];
    final source = await _source();

    // Find the txSnapshots array in the JSON string
    final arrayStart = source.indexOf('[', source.indexOf('"txSnapshots"'));
    if (arrayStart == -1) {
      logger.w('Snapshot $txId has no txSnapshots array');
      return;
    }

    var yielded = 0;
    var skipped = 0;

    // Scan for individual objects within the array
    for (final objectJson in _iterateJsonArrayObjects(source, arrayStart)) {
      Map item;
      try {
        item = jsonDecode(objectJson) as Map;
      } catch (e) {
        logger.w('Error parsing snapshot entry in $txId');
        continue;
      }

      DriveHistoryTransaction node;
      try {
        node = DriveHistoryTransaction.fromJson(item['gqlNode']);
      } catch (e) {
        logger.w('Error parsing GQLNode from snapshot item ($txId)');
        continue;
      }

      final isInRange = range.isInRange(node.block?.height ?? -1);
      if (isInRange) {
        yield DriveEntityHistoryTransactionModel(transactionCommonMixin: node);
        yielded++;

        final String? data = item['jsonMetadata'];
        if (data != null) {
          final TxID txId = node.id;
          final Uint8List dataAsBytes = Uint8List.fromList(utf8.encode(data));
          await _setDataForTxId(driveId, txId, dataAsBytes);
        }
      } else {
        skipped++;
      }
    }

    logger.d('Snapshot $txId range ${range.start}-${range.end}: '
        'yielded $yielded, skipped $skipped');

    if (currentIndex == subRanges.rangeSegments.length - 1) {
      _cachedSource = null;
      _prefetchFuture = null;
    }
  }

  /// Iterates over top-level JSON objects in an array without parsing the
  /// entire array. Uses brace counting to find object boundaries.
  ///
  /// [source] is the full JSON string. [arrayStartIndex] is the index of
  /// the opening `[` of the array.
  static Iterable<String> _iterateJsonArrayObjects(
    String source,
    int arrayStartIndex,
  ) sync* {
    var i = arrayStartIndex + 1; // skip the '['
    final len = source.length;

    while (i < len) {
      // Skip whitespace and commas
      while (i < len) {
        final c = source.codeUnitAt(i);
        if (c == 0x7D + 1) break; // shouldn't happen
        if (c == 0x5D) return; // ']' — end of array
        if (c == 0x7B) break; // '{' — start of object
        i++;
      }
      if (i >= len) return;

      // Found '{', count braces to find matching '}'
      final objectStart = i;
      var depth = 0;
      var inString = false;
      var escaped = false;

      while (i < len) {
        final c = source.codeUnitAt(i);

        if (escaped) {
          escaped = false;
          i++;
          continue;
        }

        if (c == 0x5C) {
          // backslash
          escaped = true;
          i++;
          continue;
        }

        if (c == 0x22) {
          // double quote
          inString = !inString;
          i++;
          continue;
        }

        if (!inString) {
          if (c == 0x7B) depth++; // '{'
          if (c == 0x7D) {
            // '}'
            depth--;
            if (depth == 0) {
              yield source.substring(objectStart, i + 1);
              i++;
              break;
            }
          }
        }
        i++;
      }
    }
  }

  static Future<Uint8List> _setDataForTxId(
    DriveID driveId,
    TxID txId,
    Uint8List data,
  ) async {
    final Cache<Uint8List> cache = await _lazilyInitCache(driveId);

    await cache.put(txId, data);

    // Track tx IDs per drive
    _txIdsByDrive.putIfAbsent(driveId, () => <TxID>{});
    _txIdsByDrive[driveId]!.add(txId);

    return data;
  }

  static Future<Uint8List?> getDataForTxId(
    DriveID driveId,
    TxID txId,
  ) async {
    final Cache<Uint8List> cache = await _lazilyInitCache(driveId);
    final Uint8List? value = await cache.getAndRemove(txId);

    return value;
  }

  /// Gets cached transaction IDs for all drives currently in memory.
  /// This should be called after all drives sync but before disposal.
  static Future<List<TxID>> getAllCachedTransactionIds() async {
    final allTxIds = <TxID>{};
    for (final txIds in _txIdsByDrive.values) {
      allTxIds.addAll(txIds);
    }
    return allTxIds.toList();
  }

  /// Gets cached transaction IDs for a specific drive.
  static Future<List<TxID>> getCachedTransactionIds(DriveID driveId) async {
    final txIds = _txIdsByDrive[driveId];
    return txIds?.toList() ?? [];
  }

  static Future<Cache<Uint8List>> _lazilyInitCache(DriveID driveId) async {
    // Check if cache already exists
    if (_jsonMetadataCaches.containsKey(driveId)) {
      return _jsonMetadataCaches[driveId]!;
    }

    // Check if initialization is already in progress
    if (_cacheInitFutures.containsKey(driveId)) {
      return _cacheInitFutures[driveId]!;
    }

    // Start initialization
    final initFuture = _createCache(driveId);
    _cacheInitFutures[driveId] = initFuture;

    try {
      final cache = await initFuture;
      _jsonMetadataCaches[driveId] = cache;
      return cache;
    } finally {
      // Clean up the future after initialization completes
      _cacheInitFutures.remove(driveId);
    }
  }

  /// Helper method to create a new cache instance
  static Future<Cache<Uint8List>> _createCache(DriveID driveId) async {
    final store = await newMemoryCacheStore();
    final cache = await store.cache<Uint8List>(
      name: 'snapshot-data-$driveId',
      maxEntries: 100000,
    );
    return cache;
  }

  static Future<void> dispose(DriveID driveId) async {
    // Wait for any pending initialization to complete
    final initFuture = _cacheInitFutures[driveId];
    if (initFuture != null) {
      await initFuture;
    }

    // Clear and remove cache
    final cache = _jsonMetadataCaches[driveId];
    await cache?.clear();
    _jsonMetadataCaches.remove(driveId);

    // Remove init future
    _cacheInitFutures.remove(driveId);

    // NOTE: We keep transaction IDs in _txIdsByDrive for now
    // They will be cleared after post-sync operations use them
    // via clearAllCachedTransactionIds()

    logger.d('Disposed snapshot cache for drive $driveId');
  }

  /// Clears all cached transaction IDs from all drives.
  /// Should be called after post-sync operations that use transaction IDs.
  static void clearAllCachedTransactionIds() {
    _txIdsByDrive.clear();
    logger.d('Cleared all cached transaction IDs from snapshots');
  }
}
