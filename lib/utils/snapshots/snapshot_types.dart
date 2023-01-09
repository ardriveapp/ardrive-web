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

  @JsonKey(name: 'jsonMetadata')
  String jsonMetadata;

  TxSnapshot({required this.gqlNode, required this.jsonMetadata});

  TxSnapshot.fromJson(Map<String, dynamic> json)
      : gqlNode =
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
                .fromJson(json['gqlNode'] as Map<String, dynamic>),
        jsonMetadata = json['jsonMetadata'] as String;

  toJson() => {
        'gqlNode': gqlNode,
        'jsonMetadata': jsonMetadata,
      };
}
