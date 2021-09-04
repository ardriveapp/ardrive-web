import 'package:ardrive/entities/entities.dart';

import './database/database.dart';

extension FolderEntryExtensions on FolderEntry {
  FolderEntity asEntity() => FolderEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
      );
}
