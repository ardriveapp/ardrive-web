import 'package:arweave/arweave.dart';
import 'package:json_annotation/json_annotation.dart';

part 'upload_metadata.g.dart';

abstract class UploadMetadata {}

@JsonSerializable()
class ARFSDriveUploadMetadata extends ARFSUploadMetadata {
  ARFSDriveUploadMetadata({
    required super.tags,
    required super.name,
    required super.id,
    required super.isPrivate,
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
    required super.tags,
    required super.name,
    required super.id,
    required super.isPrivate,
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
    required super.tags,
    required super.name,
    required super.id,
    required super.isPrivate,
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

// {
//   "name": "420-3",
//   "size": 420000,
//   "lastModifiedDate": 1682024476785,
//   "dataTxId": "vjjdo85A_XjpZuZV3zwEiECoArmFNqU8VizHirCoXUQ",
//   "dataContentType": "application/octet-stream"
// }

abstract class ARFSUploadMetadata extends UploadMetadata {
  final String name;
  final List<Tag> tags;
  final String id;
  final bool isPrivate;
  final List<String> paidBy;

  ARFSUploadMetadata({
    required this.name,
    required this.tags,
    required this.id,
    required this.isPrivate,
    this.paidBy = const [],
  });

  Map<String, dynamic> toJson();

  @override
  String toString() => toJson().toString();
}
