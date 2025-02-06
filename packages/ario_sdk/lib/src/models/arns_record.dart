import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'arns_record.g.dart';

@JsonSerializable()
class ARNSRecord extends Equatable {
  static const defaultTtlSeconds = 900; // 15 minutes

  final String transactionId;
  final int ttlSeconds;

  const ARNSRecord({required this.transactionId, required this.ttlSeconds});

  factory ARNSRecord.fromJson(Map<String, dynamic> json) =>
      _$ARNSRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ARNSRecordToJson(this);

  @override
  List<Object?> get props => [transactionId, ttlSeconds];
}
