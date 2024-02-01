import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/utils/custom_metadata.dart';

import './database/database.dart';

extension FileEntryExtensions on FileEntry {
  FileEntity asEntity() {
    final file = FileEntity(
      id: id,
      driveId: driveId,
      parentFolderId: parentFolderId,
      name: name,
      dataTxId: dataTxId,
      size: size,
      lastModifiedDate: lastModifiedDate,
      dataContentType: dataContentType,
      pinnedDataOwnerAddress: pinnedDataOwnerAddress,
      isHidden: isHidden,
    );

    file.customJsonMetadata = parseCustomJsonMetadata(customJsonMetadata);
    file.customGqlTags = parseCustomGqlTags(customGQLTags);

    return file;
  }
}
