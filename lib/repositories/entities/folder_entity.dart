import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'folder_entity.g.dart';

@JsonSerializable()
class FolderEntity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String driveId;
  @JsonKey(ignore: true)
  String parentFolderId;

  String name;

  FolderEntity(this.name);

  factory FolderEntity.fromRawEntity(RawEntity entity) =>
      FolderEntity.fromJson(entity.jsonData)
        ..id = entity.getTag(EntityTag.folderId)
        ..driveId = entity.getTag(EntityTag.driveId)
        ..parentFolderId = entity.getTag(EntityTag.parentFolderId);

  factory FolderEntity.fromJson(Map<String, dynamic> json) =>
      _$FolderEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FolderEntityToJson(this);
}
