import 'dart:async';
import 'dart:convert';

import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:async/async.dart';
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

  factory SnapshotItem.fromGQLNode({
    required SnapshotEntityTransaction node,
    required HeightRange subRanges,
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
      fakeSource: fakeSource,
    );
  }

  factory SnapshotItem.fromStream({
    required Stream<DriveHistoryTransaction> source,
    required int blockStart,
    required int blockEnd,
    required DriveID driveId,
    required HeightRange subRanges,
  }) {
    return SnapshotItemToBeCreated(
      blockStart: blockStart,
      blockEnd: blockEnd,
      driveId: driveId,
      subRanges: subRanges,
      source: source,
    );
  }

  /// itemStream - The result of SnapshotEntityHistory query in DESC order (newer first)
  static Stream<SnapshotItem> instantiateAll(
    Stream<SnapshotEntityTransaction> itemsStream, {
    int? lastBlockHeight,
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
        );
      } catch (e) {
        print('Ignoring snapshot transaction with wrong block range - $e');
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
      fakeSource: fakeSource,
    );
    return snapshotItem;
  }
}

class SnapshotItemToBeCreated implements SnapshotItem {
  final StreamQueue _streamQueue;
  int _currentIndex = -1;

  SnapshotItemToBeCreated({
    required this.blockStart,
    required this.blockEnd,
    required this.driveId,
    required this.subRanges,
    required Stream<DriveHistoryTransaction> source,
  }) : _streamQueue = StreamQueue(source);

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

  @override
  Stream<DriveHistoryTransaction> getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveHistoryTransaction> _getNextStream() async* {
    final Range range = subRanges.rangeSegments[currentIndex];

    while (await _streamQueue.hasNext) {
      final DriveHistoryTransaction node = (await _streamQueue.peek);
      final height = node.block!.height;

      if (range.start > height) {
        // discard items before the sub-range
        _streamQueue.skip(1);
      } else if (range.isInRange(height)) {
        // yield items in range
        yield (await _streamQueue.next) as DriveHistoryTransaction;
      } else {
        // when the stream for the latest sub-range is read, close the stream
        if (currentIndex == subRanges.rangeSegments.length - 1) {
          _streamQueue.cancel();
        }

        // return when the next item is after the sub-range
        return;
      }
    }
  }
}

class SnapshotItemOnChain implements SnapshotItem {
  final int timestamp;
  final TxID txId;
  String? _cachedSource;
  int _currentIndex = -1;

  static Vault<Uint8List>? _jsonMetadataVault;

  SnapshotItemOnChain({
    required this.blockEnd,
    required this.blockStart,
    required this.driveId,
    required this.timestamp,
    required this.txId,
    required this.subRanges,
    @visibleForTesting String? fakeSource,
  }) : _cachedSource = fakeSource;

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

    final dataBytes = await ArDriveHTTP().getAsBytes(_dataUri).catchError(
      (e) {
        print('Error while fetching Snapshot Data - $e');
      },
    );

    final dataBytesAsString = String.fromCharCodes(dataBytes.data);
    return _cachedSource = dataBytesAsString;
  }

  String get _dataUri {
    return 'https://arweave.net/$txId';
  }

  @override
  Stream<DriveHistoryTransaction> getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveHistoryTransaction> _getNextStream() async* {
    final Range range = subRanges.rangeSegments[currentIndex];

    final Map dataJson = jsonDecode(await _source());
    final List<Map> txSnapshots =
        List.castFrom<dynamic, Map>(dataJson['txSnapshots']);

    for (Map item in txSnapshots) {
      DriveHistoryTransaction node;

      try {
        node = DriveHistoryTransaction.fromJson(item['gqlNode']);
      } catch (e, s) {
        print('Error while parsing GQLNode - $e, $s');
        rethrow;
      }

      final isInRange = range.isInRange(node.block?.height ?? -1);
      if (isInRange) {
        yield node;

        final String? data = item['jsonMetadata'];
        if (data != null) {
          final TxID txId = node.id;
          final Uint8List dataAsBytes = Uint8List.fromList(utf8.encode(data));
          _setDataForTxId(txId, dataAsBytes);
        }
      }
    }

    if (currentIndex == subRanges.rangeSegments.length - 1) {
      // Done reading all data, the memory can be freed
      _cachedSource = null;
    }

    return;
  }

  static Future<Uint8List> _setDataForTxId(TxID txId, Uint8List data) async {
    final cache = await _lazilyInitCache();

    await cache.put(txId, data);
    return data;
  }

  static Future<Uint8List?> getDataForTxId(TxID txId) async {
    final Vault<Uint8List> cache = await _lazilyInitCache();

    final Uint8List? value = await cache.get(txId);
    await cache.remove(txId);

    return value;
  }

  static Future<Vault<Uint8List>> _lazilyInitCache() async {
    if (_jsonMetadataVault == null) {
      final vaultStore = await newMemoryVaultStore();
      _jsonMetadataVault = await vaultStore.vault<Uint8List>(
        name: 'snapshot-data',
      );
    }

    return _jsonMetadataVault!;
  }

  static Future<void> dispose() async {
    await _jsonMetadataVault?.clear();
  }
}
