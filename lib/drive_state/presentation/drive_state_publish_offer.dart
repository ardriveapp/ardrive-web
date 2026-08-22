/// Whether the New menu offers to publish this drive's state.
///
/// A pure function, deliberately, because it is the guard on the only path in
/// the app that spends money on an artifact, and a guard buried in a widget's
/// build method is a guard nobody can enumerate. Every combination is a row in
/// `test/drive_state/presentation/drive_state_publish_offer_test.dart`.
enum DriveStatePublishOffer {
  /// Not in the menu at all.
  hidden,

  /// In the menu, greyed out.
  disabled,

  /// In the menu, and it opens the confirmation modal.
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
/// ## Hidden versus disabled
///
/// A disabled item is a promise that something could be done here; it is worth
/// showing only when the user can plausibly make it true. That splits the
/// conditions cleanly:
///
/// - **[publishingEnabled]** — the feature is off for this build. Advertising
///   a greyed-out entry for something unreleased is noise with no remedy.
///   Hidden.
/// - **[isDriveOwner]** — `DriveStateCreationRefusal.notDriveOwner`. Not
///   something the user can become. Hidden.
/// - **[hasWritePermissions]** — on someone else's shared drive. The user
///   cannot grant themselves write access, and in practice this travels with
///   ownership. Hidden. (The neighbouring snapshot item merely disables on
///   this; a snapshot is a public read of the chain, whereas an artifact is
///   signed as the owner and, for a private drive, sealed with the drive key,
///   so the two are not the same question.)
/// - **[driveIsEmpty]** — this one the user *can* fix, by uploading a file.
///   Disabled and visible, so the menu explains why it is not available yet
///   instead of the entry silently appearing later.
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
