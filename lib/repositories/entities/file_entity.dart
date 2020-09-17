import 'package:drive/repositories/entities/entity.dart';
import 'package:json_annotation/json_annotation.dart';

import 'entities.dart';

part 'file_entity.g.dart';

DateTime _intToDateTime(int v) => DateTime.fromMillisecondsSinceEpoch(v);
int _dateTimeToInt(DateTime v) => v.millisecondsSinceEpoch;

@JsonSerializable()
class FileEntity extends Entity {
  @JsonKey(ignore: true)
  String id;
  @JsonKey(ignore: true)
  String driveId;
  @JsonKey(ignore: true)
  String parentFolderId;

  String name;
  int size;
  @JsonKey(fromJson: _intToDateTime, toJson: _dateTimeToInt)
  DateTime lastModifiedDate;
  String dataTxId;

  FileEntity(
      {this.id,
      this.driveId,
      this.parentFolderId,
      this.name,
      this.size,
      this.lastModifiedDate,
      this.dataTxId});

  factory FileEntity.fromRawEntity(RawEntity entity) {
    final commitTime = DateTime.fromMillisecondsSinceEpoch(
        int.parse(entity.getTag(EntityTag.unixTime)));

    return FileEntity.fromJson(entity.jsonData)
      ..id = entity.getTag(EntityTag.fileId)
      ..driveId = entity.getTag(EntityTag.driveId)
      ..parentFolderId = entity.getTag(EntityTag.parentFolderId)
      ..lastModifiedDate ??= commitTime
      ..ownerAddress = entity.ownerAddress
      ..commitTime = commitTime;
  }

  factory FileEntity.fromJson(Map<String, dynamic> json) =>
      _$FileEntityFromJson(json);
  Map<String, dynamic> toJson() => _$FileEntityToJson(this);
}
