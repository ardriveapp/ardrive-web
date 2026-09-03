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
///
/// Three outcomes rather than two, because an L1 upload has a third. A
/// transaction is posted **header first** and its data follows as chunks
/// (`TransactionUploader.upload`, arweave-dart v4.0.2), so a failure part-way
/// leaves a transaction that exists, is paid for, and is missing its data.
/// Reporting that as [failed] tells the user nothing was spent, and the retry
/// they are being invited to make prepares a *second* transaction and pays a
/// second time. That is [uncertain]: it carries the id, because the one thing
/// worth doing with it is looking it up before deciding.
class DriveStateUploadResult {
  /// What happened, as a value that can be switched on. [txId] alone cannot
  /// carry it: an [uncertain] result has an id and is not published.
  final DriveStateUploadOutcome outcome;

  /// The transaction id the artifact landed under, or — when [isUncertain] —
  /// the one that was posted before the upload failed. `null` when [isFailed].
  final String? txId;

  /// Why nothing was published, or what was left behind, in a sentence fit to
  /// show the user. `null` only when [isPublished].
  final String? reason;

  const DriveStateUploadResult._(this.outcome, this.txId, this.reason);

  const DriveStateUploadResult.published(String txId)
      : this._(DriveStateUploadOutcome.published, txId, null);

  const DriveStateUploadResult.failed(String reason)
      : this._(DriveStateUploadOutcome.failed, null, reason);

  /// The artifact's transaction was accepted by the network and then the
  /// upload of its data failed. Whether the data is complete is not knowable
  /// from here, and the transaction is paid for either way.
  const DriveStateUploadResult.uncertain({
    required String txId,
    required String reason,
  }) : this._(DriveStateUploadOutcome.uncertain, txId, reason);

  bool get isPublished => outcome == DriveStateUploadOutcome.published;

  /// Nothing reached the network, so nothing was spent. Deliberately **not**
  /// the complement of [isPublished] — [uncertain] is neither.
  bool get isFailed => outcome == DriveStateUploadOutcome.failed;

  bool get isUncertain => outcome == DriveStateUploadOutcome.uncertain;
}

/// The three ways [DriveStateUploader.publish] can end.
enum DriveStateUploadOutcome {
  /// The artifact is on the network, in full.
  published,

  /// Nothing was posted and nothing was spent.
  failed,

  /// A transaction was posted and paid for; its data may be incomplete.
  uncertain,
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
