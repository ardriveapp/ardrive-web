import 'dart:async';
import 'dart:convert';

import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/height_range.dart';
import 'package:ardrive/utils/snapshots/range.dart';
import 'package:ardrive/utils/snapshots/segmented_gql_data.dart';
import 'package:ardrive_network/ardrive_network.dart';
import 'package:async/async.dart';
import 'package:flutter/material.dart';

abstract class SnapshotItem implements SegmentedGQLData {
  abstract final int blockStart;
  abstract final int blockEnd;
  abstract final DriveID driveId;

  factory SnapshotItem.fromGQLNode({
    required SnapshotEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
        node,
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
  final String? _fakeSource;
  final Map<TxID, String> _txIdToDataMapping = {};
  int _currentIndex = -1;

  SnapshotItemOnChain({
    required this.blockEnd,
    required this.blockStart,
    required this.driveId,
    required this.timestamp,
    required this.txId,
    required this.subRanges,
    @visibleForTesting String? fakeSource,
  }) : _fakeSource = fakeSource;

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
    if (_fakeSource != null) {
      return _fakeSource!;
    }

    final dataBytes = await ArdriveNetwork().get(url: _dataUri, asBytes: true);
    return dataBytes.data;
  }

  get _dataUri {
    return Uri(host: 'arweave.net', scheme: 'https:', path: '/$txId');
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

    final Map dataJson = jsonDecode(await source());
    final List<Map> txSnapshots =
        List.castFrom<dynamic, Map>(dataJson['txSnapshots']);

    for (Map item in txSnapshots) {
      final node =
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              .fromJson(item['gqlNode']);

      if (range.isInRange(node.block!.height)) {
        yield node;

        final TxID txId = node.id;
        final String data = item['jsonData'];
        _txIdToDataMapping[txId] = data;
      }
    }
  }

  String? getDataForTxId(TxID txId) {
    return _txIdToDataMapping.remove(txId);
  }
}
