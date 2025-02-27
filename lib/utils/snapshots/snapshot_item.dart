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
    final blockStart =
        tags.firstWhere((element) => element.name == 'Block-Start').value;
    final blockEnd =
        tags.firstWhere((element) => element.name == 'Block-End').value;
    final driveId =
        tags.firstWhere((element) => element.name == 'Drive-Id').value;
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
        logger.e('Ignoring snapshot transaction with invalid block range', e);
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
    String? maybeBlockHeightStart =
        tags.firstWhere((tag) => tag.name == 'Block-Start').value;
    String? maybeBlockHeightEnd =
        tags.firstWhere((tag) => tag.name == 'Block-End').value;

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
  static final Set<TxID> allTxs = {};

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

  Future<String> _source() async {
    if (_cachedSource != null) {
      return _cachedSource!;
    }
    final dataBytes = await _arweave.getEntityDataFromNetwork(txId: txId);
    final dataBytesAsString = String.fromCharCodes(dataBytes);
    return _cachedSource = dataBytesAsString;
  }

  @override
  Stream<DriveEntityHistoryTransactionModel> getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveEntityHistoryTransactionModel> _getNextStream() async* {
    final Range range = subRanges.rangeSegments[currentIndex];

    final Map dataJson = jsonDecode(await _source());
    final List<Map> txSnapshots =
        List.castFrom<dynamic, Map>(dataJson['txSnapshots']);

    for (Map item in txSnapshots) {
      DriveHistoryTransaction node;

      try {
        node = DriveHistoryTransaction.fromJson(item['gqlNode']);
      } catch (e) {
        logger.w(
          'Error while parsing GQLNode from snapshot item ($txId)',
        );
        continue;
      }

      final isInRange = range.isInRange(node.block?.height ?? -1);
      if (isInRange) {
        yield DriveEntityHistoryTransactionModel(transactionCommonMixin: node);

        final String? data = item['jsonMetadata'];
        if (data != null) {
          final TxID txId = node.id;
          final Uint8List dataAsBytes = Uint8List.fromList(utf8.encode(data));
          await _setDataForTxId(driveId, txId, dataAsBytes);
        }
      }
    }

    if (currentIndex == subRanges.rangeSegments.length - 1) {
      // Done reading all data, the memory can be freed
      _cachedSource = null;
    }

    return;
  }

  static Future<Uint8List> _setDataForTxId(
    DriveID driveId,
    TxID txId,
    Uint8List data,
  ) async {
    final Cache<Uint8List> cache = await _lazilyInitCache(driveId);

    await cache.put(txId, data);
    allTxs.add(txId);
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

  static Future<List<TxID>> getAllCachedTransactionIds() async {
    return allTxs.toList();
  }

  static Future<Cache<Uint8List>> _lazilyInitCache(DriveID driveId) async {
    if (!_jsonMetadataCaches.containsKey(driveId)) {
      final store = await newMemoryCacheStore();
      final cache = await store.cache<Uint8List>(
        name: 'snapshot-data-$driveId',
        maxEntries: 100000,
      );

      _jsonMetadataCaches[driveId] = cache;
    }

    return _jsonMetadataCaches[driveId]!;
  }

  static Future<void> dispose(DriveID driveId) async {
    final cache = _jsonMetadataCaches[driveId];

    await cache?.clear();
  }
}
