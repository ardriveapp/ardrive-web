part of 'drive_state_creation_cubit.dart';

@immutable
abstract class DriveStateCreationState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DriveStateCreationInitial extends DriveStateCreationState {}

/// Exporting, sealing and pricing. Nothing has left the device, and nothing
/// will as a result of this state.
class DriveStateCreationPreparing extends DriveStateCreationState {}

/// An artifact was deliberately not produced. Carries the sentence that says
/// why, because "publishing is unavailable" with no reason is the silent
/// failure `docs/DRIVE_STATE_ARTIFACT.md` §7 exists to prevent.
class DriveStateCreationRefused extends DriveStateCreationState {
  final DriveStateCreationRefusal refusal;
  final String reason;

  /// Whether the dialog offers to sync the drive and check it again. Set by
  /// the cubit, which knows whether it can sync, for a refusal a sync can
  /// clear.
  final bool canSync;

  /// Whether the sync asked for here couldn't start, so the dialog says so
  /// rather than looking as if the button did nothing.
  final bool syncDidNotStart;

  DriveStateCreationRefused({
    required this.refusal,
    required this.reason,
    this.canSync = false,
    this.syncDidNotStart = false,
  });

  /// Whether a sync of the drive can clear this refusal.
  bool get isClearedBySync =>
      isSyncGap || refusal == DriveStateCreationRefusal.noWatermark;

  /// Whether this refusal is the D3 safety rail — the drive has a known gap,
  /// or one that cannot be ruled out. The modal says more about these than it
  /// does about a public drive or a missing wallet.
  bool get isSyncGap =>
      refusal == DriveStateCreationRefusal.syncSkippedEntities ||
      refusal == DriveStateCreationRefusal.skipStateUnknown;

  @override
  List<Object?> get props => [refusal, reason, canSync, syncDidNotStart];
}

/// Syncing the drive a refusal named, before preparing again.
class DriveStateCreationSyncing extends DriveStateCreationState {}

/// Built, sealed, priced, **unsent**. The confirmation modal renders this, and
/// only a user's click moves it on.
class DriveStateCreationReady extends DriveStateCreationState {
  final PreparedDriveStateArtifact artifact;

  /// What publishing would cost, and whether it can be paid for.
  final DriveStatePublishCost cost;

  /// The transport the user currently has selected.
  final UploadMethod method;

  DriveStateCreationReady({
    required this.artifact,
    required this.cost,
    required this.method,
  });

  /// The transport that would actually carry the artifact.
  ///
  /// A free upload is a Turbo billing outcome, not a third transport, so it
  /// goes over Turbo whatever the selector last said — the same rule
  /// `CreateSnapshotCubit._useTurboUpload` applies, and the reason the modal
  /// hides the selector entirely when the upload is free.
  UploadMethod get effectiveMethod => cost.isFree ? UploadMethod.turbo : method;

  /// Whether the confirm button does anything. The single source of truth for
  /// both the button's enabled state and the cubit's own refusal to publish.
  bool get canPublish => cost.canPayWith(effectiveMethod);

  DriveStateCreationReady copyWith({
    DriveStatePublishCost? cost,
    UploadMethod? method,
  }) =>
      DriveStateCreationReady(
        artifact: artifact,
        cost: cost ?? this.cost,
        method: method ?? this.method,
      );

  @override
  List<Object?> get props => [
        artifact.driveId,
        artifact.entityCount,
        artifact.sizeInBytes,
        artifact.blockStart,
        artifact.blockEnd,
        cost,
        method,
      ];
}

class DriveStateCreationPublishing extends DriveStateCreationState {
  final PreparedDriveStateArtifact artifact;

  DriveStateCreationPublishing(this.artifact);

  @override
  List<Object?> get props => [artifact.driveId, artifact.sizeInBytes];
}

class DriveStateCreationPublished extends DriveStateCreationState {
  final PreparedDriveStateArtifact artifact;
  final String txId;

  DriveStateCreationPublished({
    required this.artifact,
    required this.txId,
  });

  @override
  List<Object?> get props => [artifact.driveId, txId];
}

/// Something went wrong that is not a refusal: a bug, a database that went
/// away, a price that could not be established, an upload that failed.
class DriveStateCreationFailure extends DriveStateCreationState {
  /// English, for the log and for tests. The modal words [kind].
  final String message;
  final DriveStateCreationFailureKind kind;

  /// For [DriveStateCreationFailureKind.publishUncertain]: the transaction
  /// that was posted.
  final String? txId;

  DriveStateCreationFailure(
    this.message, {
    this.kind = DriveStateCreationFailureKind.publishFailed,
    this.txId,
  });

  /// Whether preparing again is safe: nothing was posted, so nothing can be
  /// paid for twice. After a publish that may have posted, it is not.
  bool get canTryAgain =>
      kind == DriveStateCreationFailureKind.costTimeout ||
      kind == DriveStateCreationFailureKind.costUnknown ||
      kind == DriveStateCreationFailureKind.prepareFailed ||
      kind == DriveStateCreationFailureKind.walletUnavailable;

  @override
  List<Object?> get props => [message, kind, txId];
}

/// What went wrong, for the modal to word in the user's language.
enum DriveStateCreationFailureKind {
  costTimeout,
  costUnknown,
  prepareFailed,
  notEnabled,
  notLoggedIn,
  walletChanged,
  walletUnavailable,
  paymentDeclined,

  /// Nothing may have been posted; check before trying again.
  publishFailed,

  /// A transaction was posted and paid for; its data may be incomplete.
  publishUncertain,

  /// The upload threw; nothing is known to have been posted.
  publishThrew,
}
