import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';

/// What drive discovery found for a wallet.
class UserDriveDiscovery {
  const UserDriveDiscovery({
    required this.drives,
    this.lockedDrives = const [],
  });

  /// The drives the session can read: every public drive, and each private
  /// one with the key that decrypted it.
  final Map<DriveEntity, DriveKey?> drives;

  /// Private drives the session has no key for. See [LockedDrive].
  final List<LockedDrive> lockedDrives;
}

/// What drive discovery does with one private drive, given its key attempt.
enum PrivateDriveVerdict {
  /// A key opened it: it is listed and written like any drive.
  readable,

  /// No key the session has opens it - the password is wrong for it, or its
  /// wallet prompt was cancelled. Listed as locked; never written.
  locked,

  /// It couldn't be read. Dropped for this pass, as before, and read again
  /// on the next: an unreachable gateway says nothing about the password.
  skipped;

  static PrivateDriveVerdict of(DriveKeyAttempt attempt) {
    if (attempt.opened) {
      return PrivateDriveVerdict.readable;
    }

    return attempt.failure == DriveUnlockFailure.unavailable
        ? PrivateDriveVerdict.skipped
        : PrivateDriveVerdict.locked;
  }
}
