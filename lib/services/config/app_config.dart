import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  final String? defaultArweaveGatewayUrl;
  @JsonKey(name: 'defaultArweaveGatewayForDataRequest')
  final SelectedGateway defaultArweaveGatewayForDataRequest;
  final bool useTurboUpload;
  final bool useTurboPayment;
  final String? defaultTurboUploadUrl;
  final String? defaultTurboPaymentUrl;
  final int allowedDataItemSizeForTurbo;
  final int autoSyncIntervalInSeconds;
  final bool enableSyncFromSnapshot;
  final String stripePublishableKey;
  final bool autoSync;
  final bool uploadThumbnails;

  AppConfig({
    this.defaultArweaveGatewayUrl,
    this.defaultArweaveGatewayForDataRequest = const SelectedGateway(
      label: 'ArDrive Turbo Gateway',
      url: 'https://ardrive.net',
    ),
    this.useTurboUpload = false,
    this.useTurboPayment = false,
    this.defaultTurboUploadUrl,
    this.defaultTurboPaymentUrl,
    required this.allowedDataItemSizeForTurbo,
    this.autoSyncIntervalInSeconds = 5 * 60,
    this.enableSyncFromSnapshot = true,
    required this.stripePublishableKey,
    this.autoSync = true,
    this.uploadThumbnails = true,
  });

  AppConfig copyWith({
    String? defaultArweaveGatewayUrl,
    SelectedGateway? defaultArweaveGatewayForDataRequest,
    bool? useTurboUpload,
    bool? useTurboPayment,
    String? defaultTurboUploadUrl,
    String? defaultTurboPaymentUrl,
    int? allowedDataItemSizeForTurbo,
    int? autoSyncIntervalInSeconds,
    bool? enableSyncFromSnapshot,
    String? stripePublishableKey,
    bool? autoSync,
    bool? uploadThumbnails,
  }) {
    return AppConfig(
      defaultArweaveGatewayUrl:
          defaultArweaveGatewayUrl ?? this.defaultArweaveGatewayUrl,
      defaultArweaveGatewayForDataRequest:
          defaultArweaveGatewayForDataRequest ??
              this.defaultArweaveGatewayForDataRequest,
      useTurboUpload: useTurboUpload ?? this.useTurboUpload,
      useTurboPayment: useTurboPayment ?? this.useTurboPayment,
      defaultTurboUploadUrl:
          defaultTurboUploadUrl ?? this.defaultTurboUploadUrl,
      defaultTurboPaymentUrl:
          defaultTurboPaymentUrl ?? this.defaultTurboPaymentUrl,
      allowedDataItemSizeForTurbo:
          allowedDataItemSizeForTurbo ?? this.allowedDataItemSizeForTurbo,
      autoSyncIntervalInSeconds:
          autoSyncIntervalInSeconds ?? this.autoSyncIntervalInSeconds,
      enableSyncFromSnapshot:
          enableSyncFromSnapshot ?? this.enableSyncFromSnapshot,
      stripePublishableKey: stripePublishableKey ?? this.stripePublishableKey,
      autoSync: autoSync ?? this.autoSync,
      uploadThumbnails: uploadThumbnails ?? this.uploadThumbnails,
    );
  }

  String getGatewayDomain() {
    return defaultArweaveGatewayForDataRequest.url.split('://').last;
  }

  String diff(AppConfig other) {
    // Compares this and the given AppConfig and returns a csv string
    /// representing the differences.

    final thisJson = toJson();
    final otherJson = other.toJson();

    final keysOfThis = thisJson.keys;
    final keysOfOther = otherJson.keys;
    final Set<String> allKeys = {...keysOfThis, ...keysOfOther};

    logger.d('All keys: $allKeys');
    logger.d('This: $thisJson');
    logger.d('Other: $otherJson');

    final List<String> diffs = [];
    for (final key in allKeys) {
      final valueOfThis = thisJson[key];
      final valueOfOther = otherJson[key];

      if (valueOfThis != valueOfOther) {
        diffs.add('$key: $valueOfThis -> $valueOfOther');
      }
    }

    return diffs.join(', ');
  }

  @override
  String toString() => 'AppConfig(${toJson()})';

  factory AppConfig.fromJson(Map<String, dynamic> json) =>
      _$AppConfigFromJson(json);
  Map<String, dynamic> toJson() => _$AppConfigToJson(this);
}
