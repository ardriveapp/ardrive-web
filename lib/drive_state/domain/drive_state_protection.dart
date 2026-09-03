import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:cryptography/cryptography.dart' show SecretKey;

/// How one drive's state artifact is protected — the drive key, or nothing at
/// all — and the only place that decision is made.
///
/// ```
/// private:  serialise -> gzip -> sign as a data item -> AES256-GCM
/// public:   serialise -> gzip -> sign as a data item
/// ```
///
/// The public path is the private one minus a layer. `Cipher` and `Cipher-IV`
/// are absent from a public artifact, and their absence is the discriminator
/// (`docs/DRIVE_STATE_ARTIFACT.md` §2.6, §3.2). Everything else — the ArFS
/// tags, the coverage claim, the entity count, the signature — is identical,
/// and the signature matters *more* without a key rather than less: it is the
/// only thing binding a public artifact to the drive's owner.
///
/// ## Why this is a type and not a boolean
///
/// The worst thing this feature could do is publish a **private** drive's
/// structure in the clear. Every name, every size, every parent-child
/// relationship, permanently, on a ledger with no delete — and unlike a
/// snapshot, which leaks the shape but not the names (§1.3), an unencrypted
/// artifact of a private drive would leak all of it.
///
/// A boolean parameter cannot stop that. `encrypt: false` is one typo, one bad
/// merge or one confused caller away at every call site, and nothing about the
/// type says which drives may pass it.
///
/// So the two variants below have private constructors and [forDrive] is the
/// only way to reach either. It takes the drive's own `privacy` column and its
/// key together, and the plaintext variant is only reachable through the
/// `public` arm. A caller does not get to assert how an artifact is protected;
/// it hands over what the drive row says and is told. **Publishing a private
/// drive in the clear is not a check that could be skipped — it is a value
/// that cannot be constructed.**
///
/// The same value is what a reader carries. On the way in the drive row is
/// trustworthy and the artifact's tags are not, so the reader cross-checks the
/// artifact's cipher-presence against this: an encrypted artifact for a public
/// drive, or a plaintext one for a private drive, is refused. See
/// [DriveStateEnvelopeCodec.open] and `DriveStateImporter`.
sealed class DriveStateProtection {
  const DriveStateProtection._();

  /// Whether an artifact under this protection carries `Cipher` and
  /// `Cipher-IV` tags. The discriminator, in both directions.
  bool get isEncrypted;

  /// Resolves the protection for a drive from the two facts that decide it:
  /// the drive's `privacy` column and the drive key, if one was obtained.
  ///
  /// Refuses rather than guessing. There is deliberately no default branch
  /// that could route an unrecognised privacy to the plaintext path — the one
  /// mistake this type exists to make impossible.
  static DriveStateProtectionResult forDrive({
    required String privacy,
    required SecretKey? driveKey,
  }) {
    switch (privacy) {
      case DrivePrivacyTag.private:
        if (driveKey == null) {
          return const DriveStateProtectionResult.refused(
            DriveStateProtectionRefusal.driveKeyUnavailable,
            'This drive is private and its key is not available, so its state '
            'cannot be sealed.',
          );
        }
        return DriveStateProtectionResult.resolved(
          DriveStateEncrypted._(driveKey),
        );

      case DrivePrivacyTag.public:
        if (driveKey != null) {
          // Unreachable through `DriveDao.getDriveKey`, which returns null for
          // a drive with no `encryptedKey` — which is what a public drive is.
          // Reaching it means the caller believes this drive is private while
          // its own row says public, and a disagreement about *the* fact this
          // type turns on is not one to settle silently in either direction.
          return const DriveStateProtectionResult.refused(
            DriveStateProtectionRefusal.unexpectedDriveKey,
            'This drive is public but a drive key was supplied for it, so its '
            'state cannot be sealed.',
          );
        }
        return const DriveStateProtectionResult.resolved(
          DriveStateUnencrypted._(),
        );

      default:
        return DriveStateProtectionResult.refused(
          DriveStateProtectionRefusal.unknownPrivacy,
          'This drive records its privacy as "$privacy", which is neither '
          'public nor private, so its state cannot be sealed.',
        );
    }
  }
}

/// A private drive's artifact: signed, then encrypted under the drive key.
final class DriveStateEncrypted extends DriveStateProtection {
  const DriveStateEncrypted._(this.driveKey) : super._();

  /// The drive key. Never leaves this object, and never travels in a payload.
  final SecretKey driveKey;

  @override
  bool get isEncrypted => true;

  @override
  String toString() => 'DriveStateEncrypted(AES256-GCM under the drive key)';
}

/// A public drive's artifact: signed, and not encrypted.
///
/// Only [DriveStateProtection.forDrive]'s `public` arm can produce one.
final class DriveStateUnencrypted extends DriveStateProtection {
  const DriveStateUnencrypted._() : super._();

  @override
  bool get isEncrypted => false;

  @override
  String toString() => 'DriveStateUnencrypted(signed, not encrypted)';
}

/// Why a drive's protection could not be resolved.
///
/// Each is a refusal to act, never an error: a producer declines to prepare an
/// artifact and a reader declines to look for one, and in both cases the app
/// carries on doing what it does today.
enum DriveStateProtectionRefusal {
  /// The drive is private and no drive key was available. Without it there is
  /// nothing to encrypt with, and a private drive is never published in the
  /// clear.
  driveKeyUnavailable,

  /// The drive is public and a drive key was supplied anyway. The caller and
  /// the drive row disagree about the drive's privacy.
  unexpectedDriveKey,

  /// The `privacy` column holds something that is neither `public` nor
  /// `private`.
  unknownPrivacy,
}

/// A resolved [DriveStateProtection], or the reason there is none.
class DriveStateProtectionResult {
  /// `null` when refused.
  final DriveStateProtection? protection;

  /// `null` when [isResolved].
  final DriveStateProtectionRefusal? refusal;

  /// Why it was refused, in a sentence fit to show a user. Empty when
  /// [isResolved].
  final String reason;

  const DriveStateProtectionResult._(
    this.protection,
    this.refusal,
    this.reason,
  );

  const DriveStateProtectionResult.resolved(DriveStateProtection protection)
      : this._(protection, null, '');

  const DriveStateProtectionResult.refused(
    DriveStateProtectionRefusal refusal,
    String reason,
  ) : this._(null, refusal, reason);

  bool get isResolved => protection != null;
  bool get isRefused => refusal != null;

  @override
  String toString() => isResolved
      ? 'DriveStateProtectionResult($protection)'
      : 'DriveStateProtectionResult(${refusal!.name}, $reason)';
}
