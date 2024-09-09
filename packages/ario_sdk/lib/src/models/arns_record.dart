import 'package:json_annotation/json_annotation.dart';

part 'arns_record.g.dart';

@JsonSerializable()
class ARNSRecord {
  final String transactionId;
  final int ttlSeconds;

  ARNSRecord({required this.transactionId, required this.ttlSeconds});

  factory ARNSRecord.fromJson(Map<String, dynamic> json) =>
      _$ARNSRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ARNSRecordToJson(this);
}
