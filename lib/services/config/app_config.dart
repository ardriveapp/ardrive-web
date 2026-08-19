import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

@JsonSerializable()
class AppConfig {
  @JsonKey(name: 'defaultArweaveGatewayUrl')
  final String? arweaveGatewayUrl;
  @JsonKey(name: 'defaultArweaveGatewayForDataRequest')
  final SelectedGateway arweaveGatewayForDataRequest;
  final bool useTurboUpload;
  final bool useTurboPayment;
  final String? defaultTurboUploadUrl;
  final String? defaultTurboPaymentUrl;
  final int allowedDataItemSizeForTurbo;
  final int autoSyncIntervalInSeconds;
  final bool enableSyncFromSnapshot;

  /// Whether a sync may read a drive's state artifact before it reads
  /// snapshots (`docs/DRIVE_STATE_ARTIFACT.md` §5).
  ///
  /// Off, unlike [enableSyncFromSnapshot]. The artifact format has not been
  /// published to chain, so no drive has one to read and turning this on can
  /// only cost a discovery query - and every failure behind it is a fallback,
  /// never a failed drive. It ships dark and is switched on deliberately.
  final bool enableSyncFromDriveState;

  /// Whether the app offers to **publish** a drive state artifact.
  ///
  /// Separate from [enableSyncFromDriveState] on purpose. Reading an artifact
  /// costs nothing and every failure behind it is a fallback; publishing one
  /// spends real money and cannot be undone. A user switching creation on to
  /// try it must not thereby start trusting artifacts during sync, and a user
  /// who wants to read artifacts must not thereby be offered a button that
  /// spends. Two risks, two switches.
  ///
  /// Off in every flavour. `docs/drive-state/DECISIONS.md` D3 makes publishing
  /// an explicit user action; this flag decides whether that action is even
  /// offered, and nothing turns it on but a person.
  final bool enableDriveStatePublishing;
  final String stripePublishableKey;
  final bool autoSync;
  final bool uploadThumbnails;
  final int? configVersion;
  final String? solanaRpcUrl;
  final String? solanaCoreProgramId;
  final String? solanaGarProgramId;
  final String? solanaArnsProgramId;
  final String? solanaAntProgramId;
  final int maxConcurrentDataFetches;

  AppConfig({
    this.arweaveGatewayUrl,
    this.arweaveGatewayForDataRequest = const SelectedGateway(
      label: 'Turbo Gateway',
      url: 'https://turbo-gateway.com',
    ),
    this.useTurboUpload = false,
    this.useTurboPayment = false,
    this.defaultTurboUploadUrl,
    this.defaultTurboPaymentUrl,
    required this.allowedDataItemSizeForTurbo,
    this.autoSyncIntervalInSeconds = 5 * 60,
    this.enableSyncFromSnapshot = true,
    this.enableSyncFromDriveState = false,
    this.enableDriveStatePublishing = false,
    required this.stripePublishableKey,
    this.autoSync = true,
    this.uploadThumbnails = true,
    this.configVersion,
    this.solanaRpcUrl,
    this.solanaCoreProgramId,
    this.solanaGarProgramId,
    this.solanaArnsProgramId,
    this.solanaAntProgramId,
    this.maxConcurrentDataFetches = 5,
  });

  AppConfig copyWith({
    String? arweaveGatewayUrl,
    SelectedGateway? arweaveGatewayForDataRequest,
    bool? useTurboUpload,
    bool? useTurboPayment,
    String? defaultTurboUploadUrl,
    String? defaultTurboPaymentUrl,
    int? allowedDataItemSizeForTurbo,
    int? autoSyncIntervalInSeconds,
    bool? enableSyncFromSnapshot,
    bool? enableSyncFromDriveState,
    bool? enableDriveStatePublishing,
    String? stripePublishableKey,
    bool? autoSync,
    bool? uploadThumbnails,
    int? configVersion,
    String? solanaRpcUrl,
    String? solanaCoreProgramId,
    String? solanaGarProgramId,
    String? solanaArnsProgramId,
    String? solanaAntProgramId,
    int? maxConcurrentDataFetches,
  }) {
    return AppConfig(
      arweaveGatewayUrl: arweaveGatewayUrl ?? this.arweaveGatewayUrl,
      arweaveGatewayForDataRequest:
          arweaveGatewayForDataRequest ?? this.arweaveGatewayForDataRequest,
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
      enableSyncFromDriveState:
          enableSyncFromDriveState ?? this.enableSyncFromDriveState,
      enableDriveStatePublishing:
          enableDriveStatePublishing ?? this.enableDriveStatePublishing,
      stripePublishableKey: stripePublishableKey ?? this.stripePublishableKey,
      autoSync: autoSync ?? this.autoSync,
      uploadThumbnails: uploadThumbnails ?? this.uploadThumbnails,
      configVersion: configVersion ?? this.configVersion,
      solanaRpcUrl: solanaRpcUrl ?? this.solanaRpcUrl,
      solanaCoreProgramId: solanaCoreProgramId ?? this.solanaCoreProgramId,
      solanaGarProgramId: solanaGarProgramId ?? this.solanaGarProgramId,
      solanaArnsProgramId: solanaArnsProgramId ?? this.solanaArnsProgramId,
      solanaAntProgramId: solanaAntProgramId ?? this.solanaAntProgramId,
      maxConcurrentDataFetches:
          maxConcurrentDataFetches ?? this.maxConcurrentDataFetches,
    );
  }

  String getGatewayDomain() {
    return arweaveGatewayForDataRequest.url.split('://').last;
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
