import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive/sync/utils/batch_processor.dart';
import 'package:ardrive/utils/snapshots/snapshot_types.dart';
import 'package:ardrive/utils/snapshots/tx_snapshot_to_snapshot_data.dart';
import 'package:ardrive_utils/ardrive_utils.dart';

import 'height_range.dart';

typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;
typedef DriveHistoryTransactionEdge
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge;
typedef DriveHistoryWithoutEntityTypeFilterTransactionEdge
    = DriveEntityHistoryWithoutEntityTypeFilter$Query$TransactionConnection$TransactionEdge;

class SnapshotItemToBeCreated {
  final HeightRange subRanges;
  final int blockStart;
  final int blockEnd;
  final DriveID driveId;
  final Stream<DriveEntityHistoryTransactionModel> source;

  int? _dataStart;
  int? _dataEnd;

  // TODO: what these values will be for a snapshot with no transactions?
  // Maybe a special value like -1? - In that case the snapshot would be ignored
  // at sync time.
  int get dataStart => _dataStart ?? -1;
  int get dataEnd => _dataEnd ?? -1;

  final Future<Uint8List> Function(TxID txId) _jsonMetadataOfTxId;

  SnapshotItemToBeCreated({
    required this.blockStart,
    required this.blockEnd,
    required this.driveId,
    required this.subRanges,
    required this.source,
    required Future<Uint8List> Function(TxID txId) jsonMetadataOfTxId,
  }) : _jsonMetadataOfTxId = jsonMetadataOfTxId;

  Stream<Uint8List> getSnapshotData() async* {
    // Convert the source Stream into a List to get all elements at once
    final nodes = await source.toList();

    final processor = BatchProcessor();
    List<TxSnapshot> results = [];
    final stream = processor.batchProcess<DriveEntityHistoryTransactionModel>(
      list: nodes,
      endOfBatchCallback: (items) async* {
        List<Future<TxSnapshot>> tasks = [];

        // Process each node concurrently
        for (var node in items) {
          tasks.add(_processNode(node.transactionCommonMixin));
        }

        results.addAll(await Future.wait(tasks));

        yield 1;
      },
      batchSize: 100,
    );

    await for (var _ in stream) {}

    // Create a stream that emits each TxSnapshot in their original order
    Stream<TxSnapshot> snapshotStream = Stream.fromIterable(results);

    Stream<Uint8List> snapshotDataStream =
        snapshotStream.transform(txSnapshotToSnapshotData);

    yield* snapshotDataStream;
  }

  Future<TxSnapshot> _processNode(TransactionCommonMixin node) async {
    _dataStart = _dataStart == null || node.block!.height < _dataStart!
        ? node.block!.height
        : _dataStart;
    _dataEnd = _dataEnd == null || node.block!.height > _dataEnd!
        ? node.block!.height
        : _dataEnd;

    if (_isSnapshotTx(node)) {
      return TxSnapshot(gqlNode: node, jsonMetadata: null);
    } else {
      var metadata = await _jsonMetadataOfTxId(node.id);
      return TxSnapshot(gqlNode: node, jsonMetadata: metadata);
    }
  }

  bool _isSnapshotTx(TransactionCommonMixin node) {
    final tags = node.tags;
    final entityTypeTags =
        tags.where((tag) => tag.name == EntityTag.entityType);

    return entityTypeTags.any((tag) => tag.value == EntityTypeTag.snapshot);
  }
}
