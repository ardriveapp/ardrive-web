import 'package:json_annotation/json_annotation.dart';

class Entity {
  @JsonKey(ignore: true)
  String ownerAddress;
}
