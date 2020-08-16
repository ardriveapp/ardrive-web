import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity {
  @JsonKey(ignore: true)
  String id;

  String rootFolderId;

  DriveEntity(this.rootFolderId);

  factory DriveEntity.fromRawEntity(RawEntity entity) =>
      DriveEntity.fromJson(entity.jsonData)
        ..id = entity.getTag(EntityTag.driveId);

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}
