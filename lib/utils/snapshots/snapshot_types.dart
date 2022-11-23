import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:json_annotation/json_annotation.dart';

abstract class SnapshotData {
  // sorted in **GQL order**
  @JsonKey(name: 'txSnapshots')
  abstract List<TxSnapshot> txSnapshots; // contains revisions as well
}

abstract class TxSnapshot {
  @JsonKey(name: 'gqlNode')
  abstract DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
      gqlNode;
  @JsonKey(name: 'jsonMetadata')
  abstract String jsonMetadata;
}
