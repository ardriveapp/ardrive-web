import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/snapshots/snapshot_types.dart';
import 'package:ardrive/utils/snapshots/tx_snapshot_to_snapshot_data.dart';

import 'height_range.dart';

typedef DriveHistoryTransaction
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

class SnapshotItemToBeCreated {
  final HeightRange subRanges;
  final int blockStart;
  final int blockEnd;
  final DriveID driveId;
  final Stream<DriveHistoryTransaction> source;

  final Future<String> Function(TxID txId) _jsonMetadataOfTxId;

  SnapshotItemToBeCreated({
    required this.blockStart,
    required this.blockEnd,
    required this.driveId,
    required this.subRanges,
    required this.source,
    required Future<String> Function(TxID txId) jsonMetadataOfTxId,
  }) : _jsonMetadataOfTxId = jsonMetadataOfTxId;

  Stream<Uint8List> getSnapshotData() async* {
    final txSnapshotStream = source.asyncMap<TxSnapshot>(
      (node) async => TxSnapshot(
        gqlNode: node,
        jsonMetadata:
            _isSnapshotTx(node) ? '' : await _jsonMetadataOfTxId(node.id),
      ),
    );

    final snapshotDataStream =
        txSnapshotStream.transform<Uint8List>(txSnapshotToSnapshotData);

    yield* snapshotDataStream;
  }

  bool _isSnapshotTx(DriveHistoryTransaction node) {
    final tags = node.tags;
    final entityTypeTags =
        tags.where((tag) => tag.name == EntityTag.entityType);

    return entityTypeTags.any((tag) => tag.value == EntityType.snapshot);
  }
}
