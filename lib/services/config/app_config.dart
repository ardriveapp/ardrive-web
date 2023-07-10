import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  final String? defaultArweaveGatewayUrl;
  final bool useTurboUpload;
  final bool useTurboPayment;
  final String? defaultTurboUploadUrl;
  final String? defaultTurboPaymentUrl;
  final int allowedDataItemSizeForTurbo;
  final bool enableQuickSyncAuthoring;
  final bool enableMultipleFileDownload;
  final bool enableVideoPreview;
  final int autoSyncIntervalInSeconds;
  final bool enableSyncFromSnapshot;
  final String stripePublishableKey;

  AppConfig({
    this.defaultArweaveGatewayUrl,
    this.useTurboUpload = false,
    this.useTurboPayment = false,
    this.defaultTurboUploadUrl,
    this.defaultTurboPaymentUrl,
    required this.allowedDataItemSizeForTurbo,
    this.enableQuickSyncAuthoring = false,
    this.enableMultipleFileDownload = false,
    this.enableVideoPreview = false,
    this.autoSyncIntervalInSeconds = 5 * 60,
    this.enableSyncFromSnapshot = true,
    required this.stripePublishableKey,
  });

  AppConfig copyWith({
    String? defaultArweaveGatewayUrl,
    bool? useTurboUpload,
    bool? useTurboPayment,
    String? defaultTurboUploadUrl,
    String? defaultTurboPaymentUrl,
    int? allowedDataItemSizeForTurbo,
    bool? enableQuickSyncAuthoring,
    bool? enableMultipleFileDownload,
    bool? enableVideoPreview,
    int? autoSyncIntervalInSeconds,
    bool? enableSyncFromSnapshot,
    String? stripePublishableKey,
  }) {
    return AppConfig(
      defaultArweaveGatewayUrl:
          defaultArweaveGatewayUrl ?? this.defaultArweaveGatewayUrl,
      useTurboUpload: useTurboUpload ?? this.useTurboUpload,
      useTurboPayment: useTurboPayment ?? this.useTurboPayment,
      defaultTurboUploadUrl:
          defaultTurboUploadUrl ?? this.defaultTurboUploadUrl,
      defaultTurboPaymentUrl:
          defaultTurboPaymentUrl ?? this.defaultTurboPaymentUrl,
      allowedDataItemSizeForTurbo:
          allowedDataItemSizeForTurbo ?? this.allowedDataItemSizeForTurbo,
      enableMultipleFileDownload:
          enableMultipleFileDownload ?? this.enableMultipleFileDownload,
      enableQuickSyncAuthoring:
          enableQuickSyncAuthoring ?? this.enableQuickSyncAuthoring,
      enableVideoPreview: enableVideoPreview ?? this.enableVideoPreview,
      autoSyncIntervalInSeconds:
          autoSyncIntervalInSeconds ?? this.autoSyncIntervalInSeconds,
      enableSyncFromSnapshot:
          enableSyncFromSnapshot ?? this.enableSyncFromSnapshot,
      stripePublishableKey: stripePublishableKey ?? this.stripePublishableKey,
    );
  }

  @override
  String toString() => 'AppConfig(${toJson()})';

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
