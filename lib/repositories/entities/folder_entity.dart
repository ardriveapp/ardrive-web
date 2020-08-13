import 'package:json_annotation/json_annotation.dart';

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

  factory FolderEntity.fromJson(Map<String, dynamic> json) =>
      _$FolderEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FolderEntityToJson(this);
}
