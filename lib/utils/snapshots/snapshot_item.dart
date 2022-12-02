import 'dart:async';
import 'dart:convert';

import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive_network/ardrive_network.dart';
import 'package:async/async.dart';

abstract class SnapshotItem implements SegmentedGQLData {
  abstract final int blockStart;
  abstract final int blockEnd;
  abstract final DriveID driveId;

  factory SnapshotItem.fromGQLNode({
    required SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
        node,
    required HeightRange subRanges,

    // for testing purposes only
    String? fakeSource,
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
    required Stream<
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
        source,
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
    Stream<SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
        itemsStream, {
    int? lastBlockHeight,
  }) async* {
    HeightRange obscuredByAccumulator = HeightRange(rangeSegments: [
      if (lastBlockHeight != null) Range(start: 0, end: lastBlockHeight),
    ]);

    await for (SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction item
        in itemsStream) {
      List<TransactionCommonMixin$Tag> tags = item.tags;
      int? blockHeightStart;
      int? blockHeightEnd;
      late Range totalRange;

      try {
        blockHeightStart = int.parse(
            tags.firstWhere((tag) => tag.name == 'Block-Start').value);
        blockHeightEnd =
            int.parse(tags.firstWhere((tag) => tag.name == 'Block-End').value);
        totalRange = Range(start: blockHeightStart, end: blockHeightEnd);
      } catch (e) {
        print('Ignoring snapshot transaction with wrong block range - $e');
        continue;
      }

      HeightRange totalHeightRange = HeightRange(rangeSegments: [totalRange]);
      HeightRange subRanges = HeightRange.difference(
        totalHeightRange,
        obscuredByAccumulator,
      );
      SnapshotItem snapshotItem = SnapshotItem.fromGQLNode(
        node: item,
        subRanges: subRanges,
      );

      print(
          'SnapshotItem instantiated - ${snapshotItem.subRanges.rangeSegments}');

      yield snapshotItem;

      obscuredByAccumulator = HeightRange.union(
        obscuredByAccumulator,
        totalHeightRange,
      );
    }
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
    required Stream<
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
        source,
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
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      _getNextStream() async* {
    final Range range = subRanges.rangeSegments[currentIndex];

    while (await _streamQueue.hasNext) {
      final DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
          node = (await _streamQueue.peek);
      final height = node.block!.height;

      if (range.start > height) {
        // discard items before the sub-range
        _streamQueue.skip(1);
      } else if (range.isInRange(height)) {
        // yield items in range
        yield (await _streamQueue.next)
            as DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;
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
  final Map<TxID, String> _txIdToDataMapping = {};
  int _currentIndex = -1;

  SnapshotItemOnChain({
    required this.blockEnd,
    required this.blockStart,
    required this.driveId,
    required this.timestamp,
    required this.txId,
    required this.subRanges,

    // for testing purposes only
    String? fakeSource,
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

  Future<String> source() async {
    if (_cachedSource != null) {
      return _cachedSource!;
    }

    final dataBytes =
        await ArdriveNetwork().getAsBytes(_dataUri.toString()).catchError(
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
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getNextStream() {
    _currentIndex++;
    if (currentIndex >= subRanges.rangeSegments.length) {
      throw SubRangeIndexOverflow(index: currentIndex);
    }

    return _getNextStream();
  }

  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      _getNextStream() async* {
    final Range range = subRanges.rangeSegments[currentIndex];

    print(
        'Snapshot item ($txId) reading item #${currentIndex + 1}/${subRanges.rangeSegments.length}');

    final Map dataJson = jsonDecode(await source());
    final List<Map> txSnapshots =
        List.castFrom<dynamic, Map>(dataJson['txSnapshots']);

    for (Map item in txSnapshots) {
      DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
          node;

      try {
        node =
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                .fromJson(item['gqlNode']);
      } catch (e, s) {
        print('Error while parsing GQLNode - $e, $s');
        rethrow;
      }

      final isInRange = range.isInRange(node.block?.height ?? -1);
      if (isInRange) {
        yield node;

        final String? data = item['jsonData'];
        if (data != null) {
          final TxID txId = node.id;
          _txIdToDataMapping[txId] = data;
        }
      }
    }

    if (currentIndex == subRanges.rangeSegments.length - 1) {
      print('Done reading snapshot item data, releasing memory');
      // Done reading all data, wiping
      _cachedSource = null;
    }

    return;
  }

  String? getDataForTxId(TxID txId) {
    return _txIdToDataMapping.remove(txId);
  }
}
