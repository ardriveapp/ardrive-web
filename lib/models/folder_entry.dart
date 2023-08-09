import 'dart:convert';

import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';

import './database/database.dart';

extension FolderEntryExtensions on FolderEntry {
  FolderEntity asEntity() {
    final folder = FolderEntity(
      id: id,
      driveId: driveId,
      parentFolderId: parentFolderId,
      name: name,
    );
    folder.customJsonMetadata =
        customJsonMetadata != null ? jsonDecode(customJsonMetadata!) : null;
    folder.customGqlTags = customGQLTags != null
        ? (jsonDecode(customGQLTags!) as List<dynamic>)
            .map((maybeTag) => Tag.fromJson(maybeTag))
            .toList()
        : null;
    return folder;
  }
}
