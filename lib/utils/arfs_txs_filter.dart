import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

final supportedArFSVersions = ['0.10', '0.11', '0.12', '0.13', '0.14'];

bool doesTagsContainValidArFSVersion(List<Tag> tags) {
  return tags.any(
    (tag) =>
        tag.name == EntityTag.arFs && supportedArFSVersions.contains(tag.value),
  );
}
