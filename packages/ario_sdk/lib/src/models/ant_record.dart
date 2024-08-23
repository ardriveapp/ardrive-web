import 'package:json_annotation/json_annotation.dart';

part 'ant_record.g.dart';

@JsonSerializable()
class AntRecord {
  final String transactionId;
  final int ttlSeconds;

  AntRecord({required this.transactionId, required this.ttlSeconds});

  factory AntRecord.fromJson(Map<String, dynamic> json) =>
      _$AntRecordFromJson(json);

  Map<String, dynamic> toJson() => _$AntRecordToJson(this);
}
