import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';

const validArFsVersions = ['0.10', '0.11', '0.12'];

// NOTE: this filter is being made in order to remove from the query
/// the ArFS tag filter, in order to make the query faster
// TODO: [PE-3398]
bool arFsTransactionsFilter(
  DriveEntityHistory$Query$TransactionConnection$TransactionEdge tx,
) {
  final tags = tx.node.tags;
  final arFsTags = tags.where((tag) => tag.name == 'ArFS');
  final arFsCorrectVersion = arFsTags.any(
    (tag) => validArFsVersions.contains(tag.value),
  );
  return arFsCorrectVersion;
}
