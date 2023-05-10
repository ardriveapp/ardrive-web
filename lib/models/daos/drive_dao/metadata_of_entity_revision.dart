import 'dart:convert';

import 'package:ardrive/models/database/database.dart';
import 'package:flutter/foundation.dart';

class MetadataOfEntityRevisionResponse {
  String metadataTxId;
  Uint8List metadata;

  MetadataOfEntityRevisionResponse({
    required this.metadataTxId,
    required this.metadata,
  });
}

MetadataOfEntityRevisionResponse? metadataOfEntityRevision<R>(R revision) {
  late final Map<String, dynamic>? maybeCustomMetaData;
  late final String metadataTxId;

  if (revision is DriveRevision) {
    maybeCustomMetaData = _metadataOfDriveRevision(revision);
    metadataTxId = revision.metadataTxId;
  } else if (revision is FolderRevision) {
    maybeCustomMetaData = _metadataOfFolderRevision(revision);
    metadataTxId = revision.metadataTxId;
  } else if (revision is FileRevision) {
    maybeCustomMetaData = _metadataOfFileRevision(revision);
    metadataTxId = revision.metadataTxId;
  } else {
    throw Exception('Unknown revision type');
  }

  if (maybeCustomMetaData != null) {
    return MetadataOfEntityRevisionResponse(
      metadata: Uint8List.fromList(
        utf8.encode(
          jsonEncode(maybeCustomMetaData),
        ),
      ),
      metadataTxId: metadataTxId,
    );
  }

  return null;
}

Map<String, dynamic>? _metadataOfDriveRevision(DriveRevision revision) {
  final maybeCustomMetaData = revision.customJsonMetaData;

  if (maybeCustomMetaData == null) {
    return null;
  }

  try {
    final Map<String, dynamic> metaData = jsonDecode(maybeCustomMetaData);
    final String driveName = revision.name;
    final String rootFolderId = revision.rootFolderId;

    metaData['name'] = driveName;
    metaData['rootFolderId'] = rootFolderId;

    return metaData;
  } catch (_) {
    throw Exception(
      'Bad custom metadata for drive revision: $maybeCustomMetaData',
    );
  }
}

Map<String, dynamic>? _metadataOfFolderRevision(FolderRevision revision) {
  final maybeCustomMetaData = revision.customJsonMetaData;

  if (maybeCustomMetaData == null) {
    return null;
  }

  try {
    final Map<String, dynamic> metaData = jsonDecode(maybeCustomMetaData);
    final String folderName = revision.name;

    metaData['name'] = folderName;

    return metaData;
  } catch (_) {
    throw Exception(
      'Bad custom metadata for folder revision: $maybeCustomMetaData',
    );
  }
}

Map<String, dynamic>? _metadataOfFileRevision(FileRevision revision) {
  final maybeCustomMetaData = revision.customJsonMetaData;

  if (maybeCustomMetaData == null) {
    return null;
  }

  try {
    final Map<String, dynamic> metaData = jsonDecode(maybeCustomMetaData);
    final String fileName = revision.name;
    final int fileSize = revision.size;
    final int fileLastModifiedDate =
        revision.lastModifiedDate.millisecondsSinceEpoch;
    final String fileDataTxId = revision.dataTxId;
    final String? fileDataContentType = revision.dataContentType;

    metaData['name'] = fileName;
    metaData['size'] = fileSize;
    metaData['lastModifiedDate'] = fileLastModifiedDate;
    metaData['dataTxId'] = fileDataTxId;
    metaData['dataContentType'] = fileDataContentType;

    return metaData;
  } catch (_) {
    throw Exception(
      'Bad custom metadata for file revision: $maybeCustomMetaData',
    );
  }
}
