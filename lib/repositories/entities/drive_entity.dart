import 'package:json_annotation/json_annotation.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity {
  @JsonKey(ignore: true)
  String id;

  String rootFolderId;

  DriveEntity();

  factory DriveEntity.fromJson(Map<String, dynamic> json) =>
      _$DriveEntityFromJson(json);
  Map<String, dynamic> toJson() => _$DriveEntityToJson(this);
}
