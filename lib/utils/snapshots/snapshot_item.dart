import 'dart:async';
import 'dart:convert';

import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:async/async.dart';
import 'package:http/http.dart' as http;

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
}

class SnapshotItemToBeCreated implements SnapshotItem {
  final StreamQueue _streamQueue;

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
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getStreamForIndex(int index) async* {
    if (index >= subRanges.rangeSegments.length) {
      print('index: $index, length: ${subRanges.rangeSegments.length}');
      throw Exception('subRangeIndex overflow!');
    }

    final Range range = subRanges.rangeSegments[index];

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
        // return when the next item is after the sub-range
        return;
      }
    }
  }
}

class SnapshotItemOnChain implements SnapshotItem {
  final int timestamp;
  final TxID txId;
  final String? _fakeSource;

  SnapshotItemOnChain({
    required this.blockEnd,
    required this.blockStart,
    required this.driveId,
    required this.timestamp,
    required this.txId,
    required this.subRanges,

    // for testing purposes only
    String? fakeSource,
  }) : _fakeSource = fakeSource;

  @override
  final HeightRange subRanges;
  @override
  final int blockStart;
  @override
  final int blockEnd;
  @override
  final DriveID driveId;

  Future<String> source() async {
    if (_fakeSource != null) {
      return _fakeSource!;
    }

    final snapshotItemData = await http.get(_dataUri);
    final String dataBytes = snapshotItemData.body;
    return dataBytes;
  }

  get _dataUri {
    return Uri(host: 'arweave.net', scheme: 'https:', path: '/$txId');
  }

  @override
  Stream<DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction>
      getStreamForIndex(int index) async* {
    if (index >= subRanges.rangeSegments.length || index < 0) {
      throw Exception('Index overflow!');
    }

    final Range range = subRanges.rangeSegments[index];

    // TODO: temporary cache the tx data

    final Map dataJson = jsonDecode(await source());
    final List<Map> txSnapshots =
        List.castFrom<dynamic, Map>(dataJson['txSnapshots']);

    final sourceInRange = txSnapshots
        .map(
          (txItem) =>
              // todo: store the data of the node
              DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                  .fromJson(txItem['gqlNode']),
        )
        .where(
          (txItem) => range.isInRange(txItem.block!.height),
        )
        .toList();

    for (DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction node
        in sourceInRange) {
      yield node;
    }
  }
}
