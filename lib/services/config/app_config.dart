import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  final String? defaultArweaveGatewayUrl;
  final bool? useTurbo;
  final String? defaultTurboUrl;
  final int? allowedDataItemSizeForTurbo;

  AppConfig({
    this.defaultArweaveGatewayUrl,
    this.useTurbo,
    this.defaultTurboUrl,
    this.allowedDataItemSizeForTurbo,
  });
  AppConfig copyWith({
    String? defaultArweaveGatewayUrl,
    bool? useTurbo,
    String? defaultTurboUrl,
    int? allowedDataItemSizeForTurbo,
  }) {
    return AppConfig(
      defaultArweaveGatewayUrl:
          defaultArweaveGatewayUrl ?? this.defaultArweaveGatewayUrl,
      useTurbo: useTurbo ?? useTurbo,
      defaultTurboUrl: defaultTurboUrl ?? defaultTurboUrl,
      allowedDataItemSizeForTurbo:
          allowedDataItemSizeForTurbo ?? allowedDataItemSizeForTurbo,
    );
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
