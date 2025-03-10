import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';

/// Converts a [FileEntity] into a [DataItemFile] for use with bundlers.
///
/// The [fileData] parameter should be a function that returns a stream of the file's data.
/// This is separated from the entity to allow for lazy loading of the file data.
DataItemFile fileEntityToDataItem({
  required FileEntity entity,
  required DataStreamGenerator fileData,
  List<Tag> additionalTags = const [],
}) {
  final tags = [
    Tag('Content-Type', entity.dataContentType ?? 'application/octet-stream'),
    Tag('File-Id', entity.id ?? ''),
    Tag('Drive-Id', entity.driveId ?? ''),
    Tag('Parent-Folder-Id', entity.parentFolderId ?? ''),
    Tag('Entity-Type', 'file'),
    if (entity.licenseTxId != null) Tag('License-Tx-Id', entity.licenseTxId!),
    ...additionalTags,
  ];

  // If the entity has custom GQL tags, add them
  if (entity.customGqlTags != null) {
    tags.addAll(entity.customGqlTags!);
  }

  return DataItemFile(
    dataSize: entity.size ?? 0,
    streamGenerator: fileData,
    tags: tags,
  );
}
