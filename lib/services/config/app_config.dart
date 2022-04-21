import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  String? defaultArweaveGatewayUrl;

  AppConfig({this.defaultArweaveGatewayUrl});

  void setDefaultGatewayUrl(String url) => defaultArweaveGatewayUrl = url;

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
