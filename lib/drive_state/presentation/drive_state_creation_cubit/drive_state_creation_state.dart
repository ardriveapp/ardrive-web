part of 'drive_state_creation_cubit.dart';

@immutable
abstract class DriveStateCreationState extends Equatable {
  @override
  List<Object?> get props => [];
}

class DriveStateCreationInitial extends DriveStateCreationState {}

/// Exporting and sealing. Nothing has left the device, and nothing will as a
/// result of this state.
class DriveStateCreationPreparing extends DriveStateCreationState {}

/// An artifact was deliberately not produced. Carries the sentence that says
/// why, because "publishing is unavailable" with no reason is the silent
/// failure `docs/DRIVE_STATE_ARTIFACT.md` §7 exists to prevent.
class DriveStateCreationRefused extends DriveStateCreationState {
  final DriveStateCreationRefusal refusal;
  final String reason;

  DriveStateCreationRefused({
    required this.refusal,
    required this.reason,
  });

  /// Whether this refusal is the D3 safety rail — the drive has a known gap,
  /// or one that cannot be ruled out. The modal says more about these than it
  /// does about a public drive or a missing wallet.
  bool get isSyncGap =>
      refusal == DriveStateCreationRefusal.syncSkippedEntities ||
      refusal == DriveStateCreationRefusal.skipStateUnknown;

  @override
  List<Object?> get props => [refusal, reason];
}

/// Built, sealed, **unsent**. The confirmation modal renders this, and only a
/// user's click moves it on.
class DriveStateCreationReady extends DriveStateCreationState {
  final PreparedDriveStateArtifact artifact;

  DriveStateCreationReady(this.artifact);

  @override
  List<Object?> get props => [
        artifact.driveId,
        artifact.entityCount,
        artifact.sizeInBytes,
        artifact.blockStart,
        artifact.blockEnd,
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
/// away, an upload seam that reported a failure.
class DriveStateCreationFailure extends DriveStateCreationState {
  final String message;

  DriveStateCreationFailure(this.message);

  @override
  List<Object?> get props => [message];
}
