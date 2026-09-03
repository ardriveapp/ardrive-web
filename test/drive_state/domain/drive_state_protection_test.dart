import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:test/test.dart';

/// The rail that decides whether a drive's artifact is encrypted.
///
/// Everything else in this feature takes the answer from here, so this is
/// where the property that matters is established: **a private drive cannot be
/// published in the clear**, not because something checks for it, but because
/// there is no way to say it.
///
/// The tests below are worth reading alongside what they *cannot* be written
/// to do. There is no test that constructs a [DriveStateUnencrypted] for a
/// private drive and asserts the codec refuses it, because that test would not
/// compile: both variants have private constructors and
/// [DriveStateProtection.forDrive] is the only way to reach either. The
/// closest a caller can get is passing the wrong `privacy` string, which is
/// the first group below.
void main() {
  final aesGcm = AesGcm.with256bits();
  late SecretKey driveKey;

  setUpAll(() async {
    driveKey = await aesGcm.newSecretKey();
  });

  group('a private drive', () {
    test('with its key resolves to the encrypted form, carrying that key', () {
      final result = DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.private,
        driveKey: driveKey,
      );

      expect(result.isResolved, isTrue, reason: result.toString());
      expect(result.refusal, isNull);

      final protection = result.protection!;
      expect(protection, isA<DriveStateEncrypted>());
      expect(protection.isEncrypted, isTrue);
      expect((protection as DriveStateEncrypted).driveKey, same(driveKey));
    });

    test('without its key is refused, and never resolved to the clear', () {
      final result = DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.private,
        driveKey: null,
      );

      expect(result.isRefused, isTrue);
      expect(result.protection, isNull);
      expect(
        result.refusal,
        DriveStateProtectionRefusal.driveKeyUnavailable,
      );
      expect(result.reason, contains('private'));
    });
  });

  group('a public drive', () {
    test('with no key resolves to the unencrypted form', () {
      final result = DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.public,
        driveKey: null,
      );

      expect(result.isResolved, isTrue, reason: result.toString());
      expect(result.protection, isA<DriveStateUnencrypted>());
      expect(result.protection!.isEncrypted, isFalse);
    });

    test('with a key is refused rather than silently ignoring it', () {
      // `DriveDao.getDriveKey` returns null for a drive with no
      // `encryptedKey`, which is what a public drive is, so this should not
      // occur. It is refused rather than tolerated because reaching it means
      // the caller believes this drive is private while the drive row says
      // public - a disagreement about the one fact this type turns on, and
      // not one to settle silently in either direction.
      final result = DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.public,
        driveKey: driveKey,
      );

      expect(result.isRefused, isTrue);
      expect(result.protection, isNull);
      expect(
        result.refusal,
        DriveStateProtectionRefusal.unexpectedDriveKey,
      );
    });
  });

  group('anything else', () {
    // The `privacy` column is a string. There is deliberately no default
    // branch that could route an unrecognised value to the plaintext path,
    // which is the one mistake this type exists to prevent - so an unknown
    // value is refused with or without a key.
    for (final privacy in ['', 'PRIVATE', 'Public', 'unknown', 'none']) {
      test('"$privacy" is refused with a key', () {
        final result = DriveStateProtection.forDrive(
          privacy: privacy,
          driveKey: driveKey,
        );

        expect(result.isRefused, isTrue);
        expect(result.refusal, DriveStateProtectionRefusal.unknownPrivacy);
      });

      test('"$privacy" is refused without a key', () {
        final result = DriveStateProtection.forDrive(
          privacy: privacy,
          driveKey: null,
        );

        expect(result.isRefused, isTrue);
        expect(result.refusal, DriveStateProtectionRefusal.unknownPrivacy);
        expect(result.protection, isNull);
      });
    }
  });

  test('no input resolves a private drive to the unencrypted form', () {
    // The property, swept rather than sampled. Every combination of the two
    // inputs is tried, and the assertion is the one that must never fail: if
    // the drive is private, whatever comes back is either a refusal or the
    // encrypted form. Never the clear.
    for (final privacy in [
      DrivePrivacyTag.private,
      DrivePrivacyTag.public,
      'something else',
      '',
    ]) {
      for (final key in [driveKey, null]) {
        final result =
            DriveStateProtection.forDrive(privacy: privacy, driveKey: key);

        if (privacy != DrivePrivacyTag.private) continue;

        expect(
          result.protection,
          anyOf(isNull, isA<DriveStateEncrypted>()),
          reason: 'privacy=$privacy key=${key == null ? 'absent' : 'present'}',
        );
      }
    }
  });

  test('the unencrypted form is reachable only through the public arm', () {
    // The structural claim, asserted the only way a test can assert it: every
    // resolution that yields the unencrypted form came from `public`. A
    // caller cannot construct one directly - the constructors are private to
    // the library - so this sweep is the whole of the surface.
    for (final privacy in [
      DrivePrivacyTag.private,
      DrivePrivacyTag.public,
      'private ',
      'PUBLIC',
      '',
    ]) {
      for (final key in [driveKey, null]) {
        final protection = DriveStateProtection.forDrive(
          privacy: privacy,
          driveKey: key,
        ).protection;

        if (protection is DriveStateUnencrypted) {
          expect(privacy, DrivePrivacyTag.public);
          expect(key, isNull);
        }
      }
    }
  });
}
