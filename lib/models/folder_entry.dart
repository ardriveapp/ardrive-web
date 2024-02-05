import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/custom_metadata.dart';

import './database/database.dart';

extension FolderEntryExtensions on FolderEntry {
  FolderEntity asEntity() {
    final folder = FolderEntity(
      id: id,
      driveId: driveId,
      parentFolderId: parentFolderId,
      name: name,
      isHidden: isHidden,
    );

    folder.customJsonMetadata = parseCustomJsonMetadata(customJsonMetadata);
    folder.customGqlTags = parseCustomGqlTags(customGQLTags);

    return folder;
  }
}
