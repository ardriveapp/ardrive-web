import 'package:json_annotation/json_annotation.dart';

part 'file_entity.g.dart';

@JsonSerializable()
class FileEntity {
  @JsonKey(ignore: true)
  String id;

  String driveId;
  String parentFolderId;

  String name;
  int dataSize;
  String dataTxId;
}
