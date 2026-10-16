/// Whether "Create snapshot" makes a drive state artifact for this drive.
///
/// Users see one term, snapshot, for both kinds. Where this is [offered],
/// every "Create snapshot" in the app makes an artifact
/// (`createsDriveStateSnapshot`); otherwise it makes the older snapshot, as
/// it always did.
///
/// A pure function, deliberately, because it is the guard on the only path in
/// the app that spends money on an artifact, and a guard buried in a widget's
/// build method is a guard nobody can enumerate. Every combination is a row in
/// `test/drive_state/presentation/drive_state_publish_offer_test.dart`.
enum DriveStatePublishOffer {
  /// Not available here: "Create snapshot" makes the older snapshot.
  hidden,

  /// Available once the drive has something in it. Until then "Create
  /// snapshot" makes the older snapshot, as before.
  disabled,

  /// "Create snapshot" opens the artifact's confirmation modal.
  offered,
}

/// Decides the offer from the four conditions that make publishing possible.
///
/// ## Privacy is not one of them
///
/// It was. The gate hid the entry for every public drive, because v1 sealed an
/// artifact under the drive key and a public drive has none. That is no longer
/// true: a public drive publishes the same artifact with the encryption step
/// absent, and gains the same thing from it — the ~420 GraphQL queries and
/// ~42,000 metadata fetches an artifact replaces, of which the per-entity
/// decryption a public drive skips anyway is a small fraction (§1.2, §2.6).
///
/// So there is no privacy parameter here at all, rather than one that is
/// always true. A parameter every caller passes the same value for is a
/// question nobody is asking, and leaving it in place would leave two call
/// sites free to answer it differently.
///
/// ## The four conditions
///
/// Any one of them unmet and "Create snapshot" makes the older snapshot:
///
/// - **[publishingEnabled]**: the feature is off for this build.
/// - **[isDriveOwner]**: `DriveStateCreationRefusal.notDriveOwner`. An
///   artifact is only found when the owner uploads it.
/// - **[hasWritePermissions]**: someone else's shared drive. In practice this
///   travels with ownership.
/// - **[driveIsEmpty]**: nothing to load faster yet. The one the user can fix,
///   by uploading a file, which is why it is [DriveStatePublishOffer.disabled]
///   rather than hidden.
///
/// The gates the service still applies behind this — the D3 skip
/// precondition, the watermark, ownership again, and the payload size — are
/// unchanged and apply to a public drive exactly as they do to a private one.
DriveStatePublishOffer driveStatePublishOffer({
  required bool publishingEnabled,
  required bool isDriveOwner,
  required bool hasWritePermissions,
  required bool driveIsEmpty,
}) {
  if (!publishingEnabled || !isDriveOwner || !hasWritePermissions) {
    return DriveStatePublishOffer.hidden;
  }

  return driveIsEmpty
      ? DriveStatePublishOffer.disabled
      : DriveStatePublishOffer.offered;
}
