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

/// Decides the offer from the five conditions that make publishing possible.
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
/// - **[isPrivateDrive]** — `DriveStateCreationRefusal.publicDriveUnsupported`.
///   A drive's privacy is fixed when it is created and there is no way to
///   change it, so a disabled item here would be permanent furniture in every
///   public drive's menu. Hidden.
/// - **[isDriveOwner]** — `DriveStateCreationRefusal.notDriveOwner`. Not
///   something the user can become. Hidden.
/// - **[hasWritePermissions]** — on someone else's shared drive. The user
///   cannot grant themselves write access, and in practice this travels with
///   ownership. Hidden. (The neighbouring snapshot item merely disables on
///   this; a snapshot is a public read of the chain, whereas an artifact is
///   sealed with a drive key and signed as the owner, so the two are not the
///   same question.)
/// - **[driveIsEmpty]** — this one the user *can* fix, by uploading a file.
///   Disabled and visible, so the menu explains why it is not available yet
///   instead of the entry silently appearing later.
DriveStatePublishOffer driveStatePublishOffer({
  required bool publishingEnabled,
  required bool isPrivateDrive,
  required bool isDriveOwner,
  required bool hasWritePermissions,
  required bool driveIsEmpty,
}) {
  if (!publishingEnabled ||
      !isPrivateDrive ||
      !isDriveOwner ||
      !hasWritePermissions) {
    return DriveStatePublishOffer.hidden;
  }

  return driveIsEmpty
      ? DriveStatePublishOffer.disabled
      : DriveStatePublishOffer.offered;
}
