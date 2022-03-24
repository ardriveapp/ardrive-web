import 'package:ardrive/entities/entities.dart';

import './database/database.dart';

extension FileEntryExtensions on FileEntry {
  FileEntity asEntity() => FileEntity(
        id: id,
        driveId: driveId,
        parentFolderId: parentFolderId,
        name: name,
        dataTxId: dataTxId,
        size: size,
        lastModifiedDate: lastModifiedDate,
        dataContentType: dataContentType,
      );
}
