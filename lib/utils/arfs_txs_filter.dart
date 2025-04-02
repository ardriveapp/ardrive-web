import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

final Set<String> supportedArFSVersionsSet = {
  '0.10',
  '0.11',
  '0.12',
  '0.13',
  '0.14',
  '0.15'
};

bool doesTagsContainValidArFSVersion(List<Tag> tags) {
  return tags.any(
    (tag) =>
        tag.name == EntityTag.arFs &&
        supportedArFSVersionsSet.contains(tag.value),
  );
}
