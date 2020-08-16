import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'file_entity.g.dart';

@JsonSerializable()
class FileEntity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String driveId;
  @JsonKey(ignore: true)
  String parentFolderId;

  String name;
  int size;
  String dataTxId;

  FileEntity(
    this.name,
    this.size,
    this.dataTxId,
  );

  factory FileEntity.fromRawEntity(RawEntity entity) =>
      FileEntity.fromJson(entity.jsonData)
        ..id = entity.getTag(EntityTag.fileId)
        ..driveId = entity.getTag(EntityTag.driveId)
        ..parentFolderId = entity.getTag(EntityTag.parentFolderId);

  factory FileEntity.fromJson(Map<String, dynamic> json) =>
      _$FileEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FileEntityToJson(this);
}
