import 'package:ardrive/utils/logger.dart';
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
  final bool enableAudioPreview;
  final int autoSyncIntervalInSeconds;
  final bool enableSyncFromSnapshot;
  final bool enableSeedPhraseLogin;
  final String stripePublishableKey;
  final bool forceNoFreeThanksToTurbo;
  final BigInt? fakeTurboCredits;
  final bool topUpDryRun;
  final bool enableMetamaskLogin;
  final bool enableSearch;

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
    this.enableAudioPreview = false,
    this.autoSyncIntervalInSeconds = 5 * 60,
    this.enableSyncFromSnapshot = true,
    this.enableSeedPhraseLogin = true,
    required this.stripePublishableKey,
    this.forceNoFreeThanksToTurbo = false,
    this.fakeTurboCredits,
    this.topUpDryRun = false,
    this.enableMetamaskLogin = false,
    this.enableSearch = false,
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
    bool? enableAudioPreview,
    int? autoSyncIntervalInSeconds,
    bool? enableSyncFromSnapshot,
    bool? enableSeedPhraseLogin,
    String? stripePublishableKey,
    bool? useNewUploader,
    bool? forceNoFreeThanksToTurbo,
    BigInt? fakeTurboCredits,
    bool? topUpDryRun,
    bool? unsetFakeTurboCredits,
    bool? enableMetamaskLogin,
    bool? enableSearch,
  }) {
    final theFakeTurboCredits = unsetFakeTurboCredits == true
        ? null
        : fakeTurboCredits ?? this.fakeTurboCredits;

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
      enableAudioPreview: enableAudioPreview ?? this.enableAudioPreview,
      autoSyncIntervalInSeconds:
          autoSyncIntervalInSeconds ?? this.autoSyncIntervalInSeconds,
      enableSyncFromSnapshot:
          enableSyncFromSnapshot ?? this.enableSyncFromSnapshot,
      enableSeedPhraseLogin:
          enableSeedPhraseLogin ?? this.enableSeedPhraseLogin,
      stripePublishableKey: stripePublishableKey ?? this.stripePublishableKey,
      forceNoFreeThanksToTurbo:
          forceNoFreeThanksToTurbo ?? this.forceNoFreeThanksToTurbo,
      fakeTurboCredits: theFakeTurboCredits,
      topUpDryRun: topUpDryRun ?? this.topUpDryRun,
      enableMetamaskLogin: enableMetamaskLogin ?? this.enableMetamaskLogin,
      enableSearch: enableSearch ?? this.enableSearch,
    );
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
