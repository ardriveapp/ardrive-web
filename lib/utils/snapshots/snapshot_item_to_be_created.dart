import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/utils/snapshots/snapshot_types.dart';
import 'package:ardrive/utils/snapshots/tx_snapshot_to_snapshot_data.dart';

import '../../entities/string_types.dart';
import '../../services/arweave/graphql/graphql_api.graphql.dart';
import 'height_range.dart';

typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

class SnapshotItemToBeCreated {
  final HeightRange subRanges;
  final int blockStart;
  final int blockEnd;
  final DriveID driveId;
  final Stream<DriveHistoryTransaction> source;

  SnapshotItemToBeCreated({
    required this.blockStart,
    required this.blockEnd,
    required this.driveId,
    required this.subRanges,
    required this.source,
  });

  Stream<Uint8List> getSnapshotData() {
    final txSnapshotStream = source.map<TxSnapshot>(
      (node) => TxSnapshot(
        gqlNode: node,
        jsonMetadata: _isSnapshotTx(node) ? '' : _jsonMetadataOfTxId(node.id),
      ),
    );

    final snapshotDataStream =
        txSnapshotStream.transform<Uint8List>(txSnapshotToSnapshotData);

    return snapshotDataStream;
  }

  bool _isSnapshotTx(DriveHistoryTransaction node) {
    final tags = node.tags;
    final entityTypeTags = tags.where((tag) => tag.name == 'Entity-Type');

    return entityTypeTags.any((tag) => tag.value == 'snapshot');
  }

  String _jsonMetadataOfTxId(String txId) {
    return "TODO";
  }
}
