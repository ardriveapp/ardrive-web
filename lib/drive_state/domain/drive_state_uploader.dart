import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';

/// The seam a prepared artifact would leave through, and the reason there is
/// nothing behind it yet.
///
/// `docs/drive-state/DECISIONS.md` D8 puts executing an upload outside this
/// branch entirely: the artifact is built and tested, and nothing in the
/// system sends it. The seam exists anyway, because a confirmation flow whose
/// confirm button goes nowhere is a flow nobody has actually checked — the
/// button is wired, the states it produces are real, and the last step is the
/// one that is deliberately absent.
///
/// When upload lands, an implementation calls `entity.asTransaction()` or
/// `entity.asDataItem()` — the entity is ready for either, and §4.4 requires
/// both to remain possible — and this interface is all that has to change.
abstract class DriveStateUploader {
  /// Publishes [artifact]. Called only from a user's explicit confirmation,
  /// never from preparation, and never from a test.
  Future<DriveStateUploadResult> publish(PreparedDriveStateArtifact artifact);
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

/// The implementation this build ships: it publishes nothing and says so.
///
/// Not a stub left by accident. D8 makes "nothing is uploaded by any agent" a
/// framework rail rather than a convention, and the way to hold a rail is to
/// have no code that could cross it — not to have code that crosses it behind
/// a flag someone can flip.
class UnwiredDriveStateUploader implements DriveStateUploader {
  const UnwiredDriveStateUploader();

  @override
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact,
  ) async =>
      const DriveStateUploadResult.failed(
        'Publishing a drive state artifact is not enabled in this build. '
        'Nothing was uploaded and nothing was spent.',
      );
}
