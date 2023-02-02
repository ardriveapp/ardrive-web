import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  final String? defaultArweaveGatewayUrl;
  final bool useTurbo;
  final String? defaultTurboUrl;
  final int? allowedDataItemSizeForTurbo;
  final bool enableQuickSyncAuthoring;

  AppConfig({
    this.defaultArweaveGatewayUrl,
    this.useTurbo = false,
    this.defaultTurboUrl,
    this.allowedDataItemSizeForTurbo,
    this.enableQuickSyncAuthoring = false,
  });
  AppConfig copyWith({
    String? defaultArweaveGatewayUrl,
    bool? useTurbo,
    String? defaultTurboUrl,
    int? allowedDataItemSizeForTurbo,
    bool? enableQuickSyncAuthoring,
  }) {
    return AppConfig(
      defaultArweaveGatewayUrl:
          defaultArweaveGatewayUrl ?? this.defaultArweaveGatewayUrl,
      useTurbo: useTurbo ?? this.useTurbo,
      defaultTurboUrl: defaultTurboUrl ?? this.defaultTurboUrl,
      allowedDataItemSizeForTurbo:
          allowedDataItemSizeForTurbo ?? this.allowedDataItemSizeForTurbo,
      enableQuickSyncAuthoring:
          enableQuickSyncAuthoring ?? this.enableQuickSyncAuthoring,
    );
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
