import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'selected_gateway.g.dart';

@JsonSerializable()
class SelectedGateway with EquatableMixin {
  final String label;
  final String url;

  const SelectedGateway({required this.label, required this.url});

  factory SelectedGateway.fromJson(Map<String, dynamic> json) =>
      _$SelectedGatewayFromJson(json);
  Map<String, dynamic> toJson() => _$SelectedGatewayToJson(this);

  @override
  List<Object?> get props => [label, url];
}
