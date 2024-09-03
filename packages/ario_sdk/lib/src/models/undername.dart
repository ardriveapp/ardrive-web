import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'undername.g.dart';

@JsonSerializable(explicitToJson: true)
class ARNSUndername extends Equatable {
  final String name;
  final String domain;
  final ARNSRecord record;

  const ARNSUndername({
    required this.name,
    required this.record,
    required this.domain,
  });

  @override
  List<Object?> get props => [name, record, domain];

  factory ARNSUndername.fromJson(Map<String, dynamic> json) =>
      _$ARNSUndernameFromJson(json);
  Map<String, dynamic> toJson() => _$ARNSUndernameToJson(this);
}
