import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:json_annotation/json_annotation.dart';

part 'app_config.g.dart';

/// Where publications live unless a config says otherwise.
const defaultPublicationGatewayUrl = 'https://ardrive.net';

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
  ///
  /// Present as a key in every flavour's `assets/config/*.json` and as a
  /// dev-tools switch, like [enableDriveStatePublishing]. "Switched on
  /// deliberately" needs somewhere to do the switching: a flag readable only
  /// from Dart source is a flag nobody can turn on, and this one being
  /// unreachable while the publishing one was not is how the app came to be
  /// able to write artifacts that no build could read.
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

  /// Whether the app offers ArNS names (docs/NAMES.md): linking a Solana
  /// wallet, naming items and the Names page. Off in every flavour until
  /// phase 1 ships; with it off nothing about names is visible.
  final bool enableArNS;

  /// The "Nothing published here" page a main name points at once its item
  /// loses the name (docs/NAMES.md, "Removing"). Null until it is uploaded.
  final String? arnsPlaceholderTxId;

  /// The ArDrive release a new publication runs (docs/PUBLICATIONS.md, "The
  /// viewer bundle"): a release manifest's transaction ID as it is, or an
  /// ArNS name, read through the gateway for the release it points at.
  /// Production and development use `ardrive`, the production release.
  /// Staging pins a fixed manifest ID of a dev build uploaded by *Staging
  /// build to Arweave*, so pages published from staging open with the viewer
  /// being tested.
  final String publicationViewer;

  /// The one gateway every publication is on, whatever the data gateway
  /// setting says (docs/PUBLICATIONS.md, "The canonical gateway"): the link
  /// the app shows and copies, every absolute URL written into a page, the
  /// `publicationViewer` name's resolution, and the warm-up after a publish.
  /// A code default, so a stored config written before the key existed gets
  /// it too.
  @JsonKey(defaultValue: defaultPublicationGatewayUrl)
  final String publicationGatewayUrl;

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
    this.enableArNS = false,
    this.arnsPlaceholderTxId,
    this.publicationViewer = 'ardrive',
    this.publicationGatewayUrl = defaultPublicationGatewayUrl,
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
    bool? enableArNS,
    String? arnsPlaceholderTxId,
    String? publicationViewer,
    String? publicationGatewayUrl,
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
      enableArNS: enableArNS ?? this.enableArNS,
      arnsPlaceholderTxId: arnsPlaceholderTxId ?? this.arnsPlaceholderTxId,
      publicationViewer: publicationViewer ?? this.publicationViewer,
      publicationGatewayUrl:
          publicationGatewayUrl ?? this.publicationGatewayUrl,
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
