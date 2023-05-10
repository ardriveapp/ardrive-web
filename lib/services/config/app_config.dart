import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  final String? defaultArweaveGatewayUrl;
  final bool useTurboUpload;
  final bool useTurboPayment;
  final String? defaultTurboUrl;
  final int? allowedDataItemSizeForTurbo;
  final bool enableQuickSyncAuthoring;
  final bool enableMultipleFileDownload;
  final bool enableVideoPreview;

  AppConfig({
    this.defaultArweaveGatewayUrl,
    this.useTurboUpload = false,
    this.useTurboPayment = false,
    this.defaultTurboUrl,
    this.allowedDataItemSizeForTurbo,
    this.enableQuickSyncAuthoring = false,
    this.enableMultipleFileDownload = false,
    this.enableVideoPreview = false,
  });

  AppConfig copyWith({
    String? defaultArweaveGatewayUrl,
    bool? useTurboUpload,
    bool? useTurboPayment,
    String? defaultTurboUrl,
    int? allowedDataItemSizeForTurbo,
    bool? enableQuickSyncAuthoring,
    bool? enableMultipleFileDownload,
    bool? enableVideoPreview,
  }) {
    return AppConfig(
      defaultArweaveGatewayUrl:
          defaultArweaveGatewayUrl ?? this.defaultArweaveGatewayUrl,
      useTurboUpload: useTurboUpload ?? this.useTurboUpload,
      useTurboPayment: useTurboPayment ?? this.useTurboPayment,
      defaultTurboUrl: defaultTurboUrl ?? this.defaultTurboUrl,
      allowedDataItemSizeForTurbo:
          allowedDataItemSizeForTurbo ?? this.allowedDataItemSizeForTurbo,
      enableMultipleFileDownload:
          enableMultipleFileDownload ?? this.enableMultipleFileDownload,
      enableQuickSyncAuthoring:
          enableQuickSyncAuthoring ?? this.enableQuickSyncAuthoring,
      enableVideoPreview: enableVideoPreview ?? this.enableVideoPreview,
    );
  }

  @override
  toString() {
    return 'AppConfig(defaultArweaveGatewayUrl: $defaultArweaveGatewayUrl, useTurboUpload: $useTurboUpload, useTurboPayment: $useTurboPayment, defaultTurboUrl: $defaultTurboUrl, allowedDataItemSizeForTurbo: $allowedDataItemSizeForTurbo, enableQuickSyncAuthoring: $enableQuickSyncAuthoring, enableMultipleFileDownload: $enableMultipleFileDownload, enableVideoPreview: $enableVideoPreview)';
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
