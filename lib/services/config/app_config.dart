import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  final String? defaultArweaveGatewayUrl;
  final bool useTurbo;
  final String? defaultTurboUrl;
  final int? allowedDataItemSizeForTurbo;
  final bool enableQuickSyncAuthoring;
  final bool enableMultipleFileDownload;
  final bool enableVideoPreview;
  final int syncTimerDurationInSeconds;

  AppConfig({
    this.defaultArweaveGatewayUrl,
    this.useTurbo = false,
    this.defaultTurboUrl,
    this.allowedDataItemSizeForTurbo,
    this.enableQuickSyncAuthoring = false,
    this.enableMultipleFileDownload = false,
    this.enableVideoPreview = false,
    this.syncTimerDurationInSeconds = 5 * 60,
  });

  AppConfig copyWith({
    String? defaultArweaveGatewayUrl,
    bool? useTurbo,
    String? defaultTurboUrl,
    int? allowedDataItemSizeForTurbo,
    bool? enableQuickSyncAuthoring,
    bool? enableMultipleFileDownload,
    bool? enableVideoPreview,
    int? syncTimerDurationInSeconds,
  }) {
    return AppConfig(
      defaultArweaveGatewayUrl:
          defaultArweaveGatewayUrl ?? this.defaultArweaveGatewayUrl,
      useTurbo: useTurbo ?? this.useTurbo,
      defaultTurboUrl: defaultTurboUrl ?? this.defaultTurboUrl,
      allowedDataItemSizeForTurbo:
          allowedDataItemSizeForTurbo ?? this.allowedDataItemSizeForTurbo,
      enableMultipleFileDownload:
          enableMultipleFileDownload ?? this.enableMultipleFileDownload,
      enableQuickSyncAuthoring:
          enableQuickSyncAuthoring ?? this.enableQuickSyncAuthoring,
      enableVideoPreview: enableVideoPreview ?? this.enableVideoPreview,
      syncTimerDurationInSeconds:
          syncTimerDurationInSeconds ?? this.syncTimerDurationInSeconds,
    );
  }

  @override
  toString() {
    return 'AppConfig(defaultArweaveGatewayUrl: $defaultArweaveGatewayUrl, useTurbo: $useTurbo, defaultTurboUrl: $defaultTurboUrl, allowedDataItemSizeForTurbo: $allowedDataItemSizeForTurbo, enableQuickSyncAuthoring: $enableQuickSyncAuthoring, enableMultipleFileDownload: $enableMultipleFileDownload, enableVideoPreview: $enableVideoPreview)';
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
