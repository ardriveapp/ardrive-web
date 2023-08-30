import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';

final supportedArFSVersions = ['0.10', '0.11', '0.12', '0.13'];

bool doesTagsContainValidArFSVersion(List<TransactionCommonMixin$Tag> tags) {
  return tags.any(
    (tag) =>
        tag.name == EntityTag.arFs && supportedArFSVersions.contains(tag.value),
  );
}
