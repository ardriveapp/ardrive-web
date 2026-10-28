part of 'publish_cubit.dart';

/// Where the publish dialog is (docs/PUBLICATIONS.md, "The publish dialog").
enum PublishStage {
  loading,

  /// Something stops publishing; [PublishState.blocked] says what.
  blocked,

  included,
  look,

  /// Working out the snapshot and the cost, on the way to [review].
  pricing,

  /// Syncing the drive, from [blocked] by a sync, to check it again after.
  syncing,
  review,
  publishing,
  failed,
  done,
}

/// Why a scope cannot be published right now.
enum PublishBlock {
  /// The drive is syncing, or has not been fully read on this device: the
  /// sentence is the sync check's own.
  sync,
  pendingUploads,
  hiddenFolder,
  empty,

  /// The release could not be read, or a new snapshot was refused: the
  /// sentence says which.
  other,
}

/// A picked image: its preview and the page files it makes, or the files an
/// earlier version uploaded.
class PickedImage extends Equatable {
  const PickedImage(
      {required this.preview, required this.image, this.isSmall = false});

  /// Null when an earlier version's image could not be read back: it is
  /// still published as it was.
  final ui.Image? preview;
  final PublicationImage image;

  /// Smaller than it is shown, so it will look soft.
  final bool isSmall;

  @override
  List<Object?> get props => [preview, image, isSmall];
}

/// A licence for the whole publication.
class PublicationLicence extends Equatable {
  const PublicationLicence(this.meta, [this.params = const {}]);

  final LicenseMeta meta;

  /// A UDL's parameters, as its tags name them.
  final Map<String, String> params;

  Map<String, Object> toJson() => {
        'name': meta.name,
        'shortName': meta.shortName,
        'definitionTxId': meta.licenseDefinitionTxId,
        if (params.isNotEmpty) 'params': params,
      };

  @override
  List<Object?> get props => [meta, params];
}

class PublishState extends Equatable {
  const PublishState({
    required this.stage,
    this.blocked,
    this.blockedReason = '',
    this.summary,
    this.title = '',
    this.description = '',
    this.ownerName = '',
    this.keywords = const [],
    this.licence,
    this.icon,
    this.cover,
    this.social,
    this.iconTint,
    this.reusesSnapshot = false,
    this.cost,
    this.method = UploadMethod.turbo,
    this.step,
    this.failure = '',
    this.paidTxId,
    this.canRetry = true,
    this.link,
    this.isUpdate = false,
    this.imageError,
    this.names,
    this.naming = const [],
    this.namingStarted = false,
  });

  final PublishStage stage;

  /// The names after publishing, when the name step had work.
  final ArNSFlowOutcome? names;

  /// The names a running publish points at the page, its last step; empty
  /// when it has none.
  final List<String> naming;

  /// Whether that last step has begun: the page is up and the names are
  /// being changed, which may wait on the ArNS wallet.
  final bool namingStarted;
  final PublishBlock? blocked;
  final String blockedReason;
  final PublicationSummary? summary;

  final String title;
  final String description;
  final String ownerName;
  final List<String> keywords;
  final PublicationLicence? licence;
  final PickedImage? icon;
  final PickedImage? cover;

  /// The owner's own card; null for the generated one.
  final PickedImage? social;
  final Color? iconTint;

  final bool reusesSnapshot;
  final DriveStatePublishCost? cost;
  final UploadMethod method;

  final PublicationStep? step;
  final String failure;

  /// A transaction that reached the network before a failure.
  final String? paidTxId;

  /// Whether Try again can finish the job without paying twice.
  final bool canRetry;

  /// The publication's link, once published.
  final String? link;

  /// An update of an existing publication.
  final bool isUpdate;

  /// Why the last picked image was not used, for the field that picked it.
  final ({
    PublicationImageSlot slot,
    PublicationImageProblem problem
  })? imageError;

  bool get titleIsValid => title.trim().isNotEmpty;

  bool get canPublish => cost != null && cost!.canPayWith(method);

  PublishState copyWith({
    PublishStage? stage,
    PublishBlock? blocked,
    String? blockedReason,
    PublicationSummary? summary,
    String? title,
    String? description,
    String? ownerName,
    List<String>? keywords,
    PublicationLicence? Function()? licence,
    PickedImage? Function()? icon,
    PickedImage? Function()? cover,
    PickedImage? Function()? social,
    Color? Function()? iconTint,
    bool? reusesSnapshot,
    DriveStatePublishCost? cost,
    UploadMethod? method,
    PublicationStep? step,
    String? failure,
    String? Function()? paidTxId,
    bool? canRetry,
    String? link,
    bool? isUpdate,
    ({PublicationImageSlot slot, PublicationImageProblem problem})? Function()?
        imageError,
    ArNSFlowOutcome? names,
    List<String>? naming,
    bool? namingStarted,
  }) =>
      PublishState(
        stage: stage ?? this.stage,
        blocked: blocked ?? this.blocked,
        blockedReason: blockedReason ?? this.blockedReason,
        summary: summary ?? this.summary,
        title: title ?? this.title,
        description: description ?? this.description,
        ownerName: ownerName ?? this.ownerName,
        keywords: keywords ?? this.keywords,
        licence: licence != null ? licence() : this.licence,
        icon: icon != null ? icon() : this.icon,
        cover: cover != null ? cover() : this.cover,
        social: social != null ? social() : this.social,
        iconTint: iconTint != null ? iconTint() : this.iconTint,
        reusesSnapshot: reusesSnapshot ?? this.reusesSnapshot,
        cost: cost ?? this.cost,
        method: method ?? this.method,
        step: step ?? this.step,
        failure: failure ?? this.failure,
        paidTxId: paidTxId != null ? paidTxId() : this.paidTxId,
        canRetry: canRetry ?? this.canRetry,
        link: link ?? this.link,
        isUpdate: isUpdate ?? this.isUpdate,
        imageError: imageError != null ? imageError() : this.imageError,
        names: names ?? this.names,
        naming: naming ?? this.naming,
        namingStarted: namingStarted ?? this.namingStarted,
      );

  @override
  List<Object?> get props => [
        stage,
        blocked,
        blockedReason,
        summary,
        title,
        description,
        ownerName,
        keywords,
        licence,
        icon,
        cover,
        social,
        iconTint,
        reusesSnapshot,
        cost,
        method,
        step,
        failure,
        paidTxId,
        canRetry,
        link,
        isUpdate,
        imageError,
        names,
        naming,
        namingStarted,
      ];
}

/// Which image field.
enum PublicationImageSlot { icon, cover, social }
