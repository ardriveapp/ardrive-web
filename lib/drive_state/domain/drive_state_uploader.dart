import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';

/// The seam a prepared artifact leaves through.
///
/// `docs/drive-state/DECISIONS.md` D8 — "built and tested, never executed by
/// the loop" — is still in force and is what shapes this file. The capability
/// now exists, and the rail did not move: nothing reaches [publish] except a
/// person pressing the confirm button in
/// `drive_state_creation_modal.dart`. Preparation does not call it, no timer
/// calls it, no retry re-enters it, and no test lets a real implementation
/// past a mock.
///
/// An implementation calls `entity.asTransaction()` or `entity.asDataItem()`
/// depending on [UploadMethod] — the entity is ready for either, and
/// `docs/DRIVE_STATE_ARTIFACT.md` §4.4 requires both to remain possible, so
/// that the format survives Turbo disappearing and works for a user with
/// nothing but an Arweave wallet.
abstract class DriveStateUploader {
  /// Publishes [artifact] over [method]. Called only from a user's explicit
  /// confirmation, never from preparation, and never against a real network
  /// from a test.
  ///
  /// [method] is the transport the user chose and paid for, resolved by the
  /// cubit — a free Turbo upload arrives here as [UploadMethod.turbo], since
  /// "free" is a Turbo billing outcome and not a third transport.
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact, {
    required UploadMethod method,
  });
}

/// What an upload did, or why it did not happen.
class DriveStateUploadResult {
  /// The transaction id the artifact landed under. `null` when [isFailed].
  final String? txId;

  /// Why nothing was published, in a sentence fit to show the user.
  final String? reason;

  const DriveStateUploadResult._(this.txId, this.reason);

  const DriveStateUploadResult.published(String txId) : this._(txId, null);

  const DriveStateUploadResult.failed(String reason) : this._(null, reason);

  bool get isPublished => txId != null;
  bool get isFailed => txId == null;
}

/// The implementation used whenever publishing is switched off: it publishes
/// nothing and says so.
///
/// Not a stub left by accident, and not dead code now that a real uploader
/// exists. `AppConfig.enableDriveStatePublishing` gates the menu item, and
/// this class gates the flow a second time from the other end — with the flag
/// off, `promptToCreateDriveState` hands the cubit an uploader that has no
/// network collaborator to reach. The way to hold a rail is to have no code
/// that could cross it, rather than code that crosses it behind a boolean
/// somebody can get wrong.
class UnwiredDriveStateUploader implements DriveStateUploader {
  const UnwiredDriveStateUploader();

  @override
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact, {
    required UploadMethod method,
  }) async =>
      const DriveStateUploadResult.failed(
        'Publishing a drive state artifact is not enabled in this build. '
        'Nothing was uploaded and nothing was spent.',
      );
}
