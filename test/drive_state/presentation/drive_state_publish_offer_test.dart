import 'package:ardrive/drive_state/presentation/drive_state_publish_offer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The visibility matrix for the New menu's "Publish Drive State" item.
///
/// Enumerated rather than sampled. This is the guard on the only path in the
/// app that spends money on an artifact, so "the conditions I thought of" is
/// not a standard it can be held to — all 32 combinations are asserted, and
/// each condition is additionally pinned on its own so that a regression names
/// itself.
void main() {
  DriveStatePublishOffer offerWith({
    bool publishingEnabled = true,
    bool isPrivateDrive = true,
    bool isDriveOwner = true,
    bool hasWritePermissions = true,
    bool driveIsEmpty = false,
  }) =>
      driveStatePublishOffer(
        publishingEnabled: publishingEnabled,
        isPrivateDrive: isPrivateDrive,
        isDriveOwner: isDriveOwner,
        hasWritePermissions: hasWritePermissions,
        driveIsEmpty: driveIsEmpty,
      );

  group('every condition met', () {
    test('a private, non-empty, owned drive with the flag on is offered', () {
      expect(offerWith(), DriveStatePublishOffer.offered);
    });
  });

  group('hidden, because the user cannot make the condition true', () {
    test('the feature flag is off', () {
      expect(
        offerWith(publishingEnabled: false),
        DriveStatePublishOffer.hidden,
      );
    });

    test('the drive is public, which no user can change', () {
      expect(offerWith(isPrivateDrive: false), DriveStatePublishOffer.hidden);
    });

    test('the signed-in wallet does not own the drive', () {
      expect(offerWith(isDriveOwner: false), DriveStatePublishOffer.hidden);
    });

    test('the drive is not writable by this user', () {
      expect(
        offerWith(hasWritePermissions: false),
        DriveStatePublishOffer.hidden,
      );
    });

    test('hiding wins over disabling when both apply', () {
      expect(
        offerWith(publishingEnabled: false, driveIsEmpty: true),
        DriveStatePublishOffer.hidden,
      );
    });
  });

  group('disabled, because the user can fix it by uploading something', () {
    test('an empty drive is shown, greyed out', () {
      expect(offerWith(driveIsEmpty: true), DriveStatePublishOffer.disabled);
    });
  });

  test('all 32 combinations agree with the stated rule', () {
    for (var mask = 0; mask < 32; mask++) {
      final publishingEnabled = mask & 1 != 0;
      final isPrivateDrive = mask & 2 != 0;
      final isDriveOwner = mask & 4 != 0;
      final hasWritePermissions = mask & 8 != 0;
      final driveIsEmpty = mask & 16 != 0;

      final expected = !publishingEnabled ||
              !isPrivateDrive ||
              !isDriveOwner ||
              !hasWritePermissions
          ? DriveStatePublishOffer.hidden
          : driveIsEmpty
              ? DriveStatePublishOffer.disabled
              : DriveStatePublishOffer.offered;

      expect(
        driveStatePublishOffer(
          publishingEnabled: publishingEnabled,
          isPrivateDrive: isPrivateDrive,
          isDriveOwner: isDriveOwner,
          hasWritePermissions: hasWritePermissions,
          driveIsEmpty: driveIsEmpty,
        ),
        expected,
        reason: 'publishingEnabled: $publishingEnabled, '
            'isPrivateDrive: $isPrivateDrive, '
            'isDriveOwner: $isDriveOwner, '
            'hasWritePermissions: $hasWritePermissions, '
            'driveIsEmpty: $driveIsEmpty',
      );
    }
  });

  test('nothing is ever offered while the feature flag is off', () {
    for (var mask = 0; mask < 16; mask++) {
      expect(
        driveStatePublishOffer(
          publishingEnabled: false,
          isPrivateDrive: mask & 1 != 0,
          isDriveOwner: mask & 2 != 0,
          hasWritePermissions: mask & 4 != 0,
          driveIsEmpty: mask & 8 != 0,
        ),
        DriveStatePublishOffer.hidden,
      );
    }
  });
}
