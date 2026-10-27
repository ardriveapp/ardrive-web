import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'arns_record.g.dart';

@JsonSerializable()
class ARNSRecord extends Equatable {
  /// docs/NAMES.md: 5 minutes, always sent (Turbo would default to 3600).
  static const defaultTtlSeconds = 300;

  final String transactionId;
  final int ttlSeconds;

  const ARNSRecord({required this.transactionId, required this.ttlSeconds});

  factory ARNSRecord.fromJson(Map<String, dynamic> json) =>
      _$ARNSRecordFromJson(json);

  Map<String, dynamic> toJson() => _$ARNSRecordToJson(this);

  @override
  List<Object?> get props => [transactionId, ttlSeconds];
}
