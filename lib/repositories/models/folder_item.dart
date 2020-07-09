import 'dart:convert';

import 'package:json_annotation/json_annotation.dart';
import 'package:moor/moor.dart';

part 'folder_item.g.dart';

@JsonSerializable()
class FolderItem {
  String id;
  bool isSubfolder;
  bool isHidden;

  FolderItem({this.id, this.isSubfolder, this.isHidden});

  factory FolderItem.fromJson(Map<String, dynamic> json) =>
      _$FolderItemFromJson(json);
  Map<String, dynamic> toJson() => _$FolderItemToJson(this);
}

class FolderItemsConverter extends TypeConverter<List<FolderItem>, String> {
  const FolderItemsConverter();

  @override
  List<FolderItem> mapToDart(String fromDb) {
    if (fromDb == null) {
      return null;
    }
    return (json.decode(fromDb) as List)
        .map((i) => FolderItem.fromJson(i))
        .toList();
  }

  @override
  String mapToSql(List<FolderItem> value) {
    if (value == null) {
      return null;
    }

    return json.encode(value);
  }
}
