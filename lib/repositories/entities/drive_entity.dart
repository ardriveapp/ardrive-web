import 'package:json_annotation/json_annotation.dart';

part 'drive_entity.g.dart';

@JsonSerializable()
class DriveEntity {
  @JsonKey(ignore: true)
  String id;

  String rootFolderId;
}
