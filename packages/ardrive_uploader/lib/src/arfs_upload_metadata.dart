import 'package:arweave/arweave.dart';
import 'package:json_annotation/json_annotation.dart';

part 'arfs_upload_metadata.g.dart';

abstract class UploadMetadata {}

@JsonSerializable()
class ARFSDriveUploadMetadata extends ARFSUploadMetadata {
  ARFSDriveUploadMetadata({
    required super.entityMetadataTags,
    required super.name,
    required super.id,
    required super.isPrivate,
    required super.dataItemTags,
    required super.bundleTags,
  });

  @override
  Map<String, dynamic> toJson() => _$ARFSDriveUploadMetadataToJson(this);
}

@JsonSerializable()
class ARFSFolderUploadMetatadata extends ARFSUploadMetadata {
  final String driveId;
  final String? parentFolderId;

  ARFSFolderUploadMetatadata({
    required this.driveId,
    this.parentFolderId,
    required super.entityMetadataTags,
    required super.name,
    required super.id,
    required super.isPrivate,
    required super.dataItemTags,
    required super.bundleTags,
  });

  @override
  Map<String, dynamic> toJson() => _$ARFSFolderUploadMetatadataToJson(this);
}

@JsonSerializable()
class ARFSFileUploadMetadata extends ARFSUploadMetadata {
  final int size;
  final DateTime lastModifiedDate;
  final String dataContentType;
  final String driveId;
  final String parentFolderId;

  ARFSFileUploadMetadata({
    required this.size,
    required this.lastModifiedDate,
    required this.dataContentType,
    required this.driveId,
    required this.parentFolderId,
    required super.entityMetadataTags,
    required super.name,
    required super.id,
    required super.isPrivate,
    required super.dataItemTags,
    required super.bundleTags,
  });

  // without dataTxId
  @override
  Map<String, dynamic> toJson() => {
        'name': name,
        'size': size,
        'lastModifiedDate': lastModifiedDate.millisecondsSinceEpoch,
        'dataContentType': dataContentType,
      };
}

abstract class ARFSUploadMetadata extends UploadMetadata {
  final String id;
  final String name;
  final List<Tag> entityMetadataTags;
  final List<Tag> dataItemTags;
  final List<Tag> bundleTags;
  final bool isPrivate;

  ARFSUploadMetadata({
    required this.name,
    required this.entityMetadataTags,
    required this.dataItemTags,
    required this.bundleTags,
    required this.id,
    required this.isPrivate,
  });

  Map<String, dynamic> toJson();

  @override
  String toString() => toJson().toString();
}
