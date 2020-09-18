import 'package:arweave/arweave.dart';
import 'package:json_annotation/json_annotation.dart';

abstract class Entity {
  @JsonKey(ignore: true)
  String ownerAddress;
  @JsonKey(ignore: true)
  DateTime commitTime;

  Transaction asTransaction();
}
