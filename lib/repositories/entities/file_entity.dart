import 'package:json_annotation/json_annotation.dart';

part 'file_entity.g.dart';

@JsonSerializable()
class FileEntity {
  @JsonKey(ignore: true)
  String id;

  String parentFolderId;

  String name;
  int size;
  String dataTxId;
}
