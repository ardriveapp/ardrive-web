import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:json_annotation/json_annotation.dart';

abstract class SnapshotData {
  // sorted in **GQL order**
  @JsonKey(name: 'txSnapshots')
  abstract List<TxSnapshot> txSnapshots; // contains revisions as well
}

class TxSnapshot {
  @JsonKey(name: 'gqlNode')
  DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
      gqlNode;

  @JsonKey(
    name: 'jsonMetadata',
  )
  Uint8List? jsonMetadata;

  TxSnapshot({required this.gqlNode, required this.jsonMetadata});

  TxSnapshot.fromJson(Map<String, dynamic> json)
      : gqlNode =
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                .fromJson(json['gqlNode'] as Map<String, dynamic>),
        jsonMetadata =
            Uint8List.fromList(utf8.encode(json['jsonMetadata'] as String));

  toJson() => {
        'gqlNode': gqlNode,
        'jsonMetadata':
            jsonMetadata != null ? utf8.decode(jsonMetadata!) : null,
      };
}
