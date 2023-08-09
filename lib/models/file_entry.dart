import 'dart:convert';

import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';

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
    );
    file.customJsonMetadata =
        customJsonMetadata != null ? jsonDecode(customJsonMetadata!) : null;
    file.customGqlTags = customGQLTags != null
        ? (jsonDecode(customGQLTags!) as List<dynamic>)
            .map((maybeTag) => Tag.fromJson(maybeTag))
            .toList()
        : null;
    return file;
  }
}
