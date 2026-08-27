import 'package:ardrive/drive_state/presentation/drive_state_publish_offer.dart';
import 'package:flutter_test/flutter_test.dart';

/// The visibility matrix for the New menu's "Publish Drive State" item.
///
/// Enumerated rather than sampled. This is the guard on the only path in the
/// app that spends money on an artifact, so "the conditions I thought of" is
/// not a standard it can be held to — all 16 combinations are asserted, and
/// each condition is additionally pinned on its own so that a regression names
/// itself.
///
/// Sixteen and not thirty-two: privacy used to be a fifth condition and is no
/// longer one. A public drive publishes the same artifact with the encryption
/// step absent, so the gate has nothing to ask about it. The group below pins
/// that the parameter is gone rather than merely defaulted true.
void main() {
  DriveStatePublishOffer offerWith({
    bool publishingEnabled = true,
    bool isDriveOwner = true,
    bool hasWritePermissions = true,
    bool driveIsEmpty = false,
  }) =>
      driveStatePublishOffer(
        publishingEnabled: publishingEnabled,
        isDriveOwner: isDriveOwner,
        hasWritePermissions: hasWritePermissions,
        driveIsEmpty: driveIsEmpty,
      );

  group('every condition met', () {
    test('a non-empty, owned drive with the flag on is offered', () {
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

  group('privacy is not a condition', () {
    // The gate used to hide the entry for every public drive. It cannot any
    // more, because there is nowhere left to say so: these tests are the
    // record that the parameter was removed rather than left defaulting to
    // `true`, which would read the same from the two call sites and behave
    // the same only until one of them passed something else.
    //
    // A public drive reaching `offered` is asserted by every row above — none
    // of them mentions privacy — and by the exhaustive sweep below, whose
    // 16 rows are the *whole* input space of this function.
    test('the gate has exactly four inputs, and none of them is privacy', () {
      // Compiles only while `isPrivateDrive` is not a parameter: adding it
      // back as required breaks this call, and adding it back as optional
      // leaves the sweep below asserting an input space that is no longer
      // whole. Both are the failure this pins.
      expect(
        driveStatePublishOffer(
          publishingEnabled: true,
          isDriveOwner: true,
          hasWritePermissions: true,
          driveIsEmpty: false,
        ),
        DriveStatePublishOffer.offered,
      );
    });
  });

  test('all 16 combinations agree with the stated rule', () {
    for (var mask = 0; mask < 16; mask++) {
      final publishingEnabled = mask & 1 != 0;
      final isDriveOwner = mask & 2 != 0;
      final hasWritePermissions = mask & 4 != 0;
      final driveIsEmpty = mask & 8 != 0;

      final expected =
          !publishingEnabled || !isDriveOwner || !hasWritePermissions
              ? DriveStatePublishOffer.hidden
              : driveIsEmpty
                  ? DriveStatePublishOffer.disabled
                  : DriveStatePublishOffer.offered;

      expect(
        driveStatePublishOffer(
          publishingEnabled: publishingEnabled,
          isDriveOwner: isDriveOwner,
          hasWritePermissions: hasWritePermissions,
          driveIsEmpty: driveIsEmpty,
        ),
        expected,
        reason: 'publishingEnabled: $publishingEnabled, '
            'isDriveOwner: $isDriveOwner, '
            'hasWritePermissions: $hasWritePermissions, '
            'driveIsEmpty: $driveIsEmpty',
      );
    }
  });

  test('nothing is ever offered while the feature flag is off', () {
    for (var mask = 0; mask < 8; mask++) {
      expect(
        driveStatePublishOffer(
          publishingEnabled: false,
          isDriveOwner: mask & 1 != 0,
          hasWritePermissions: mask & 2 != 0,
          driveIsEmpty: mask & 4 != 0,
        ),
        DriveStatePublishOffer.hidden,
      );
    }
  });
}
