/// Turning an artifact database into something publishable, and back.
///
/// ```
/// private:  sqlite bytes -> gzip -> sign as a data item -> AES256-GCM
/// public:   sqlite bytes -> gzip -> sign as a data item
/// ```
///
/// **Why the signature is inside the encryption, and why it is a data item.**
/// Signing binds the owner to the content rather than to a transaction header.
/// A bundled data item has no L1 header — `GET /tx/<id>` returns 404 for one,
/// and its owner is knowable only through the GraphQL indexer — so a signature
/// on the payload is what lets a bundled artifact and a top-level one verify
/// identically. That in turn is what keeps the transport a purely operational
/// choice, with no bearing on trust.
///
/// **Why gzip comes before signing.** Compressing after signing would mean the
/// signature covers bytes nobody transmits. Compressing before means the
/// signed bytes are the transmitted bytes.
library;

import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_entity.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:arweave/utils.dart' as arweave_utils;
import 'package:cryptography/cryptography.dart' show Mac, SecretBox, SecretKey;

/// Why a sealed artifact could not be opened.
///
/// As everywhere else in this format, each is a fallback: log the reason, sync
/// the ordinary way. Never fail the drive.
enum ArtifactSealFailure {
  /// The `Cipher` tag names something other than AES256-GCM. Reading one of
  /// those would mean trusting unauthenticated bytes, which is the thing this
  /// format refuses to do.
  unsupportedCipher,

  /// A private drive's artifact declaring no cipher, or a public drive's
  /// declaring one.
  privacyMismatch,

  /// The body did not decrypt. GCM cannot tell a wrong key from wrong bytes,
  /// and does not have to — both mean this artifact is unusable. Gateways have
  /// been observed serving bodies that arrived wrong; this is what catches it.
  decryptionFailed,

  /// The signed bytes are not a gzip stream.
  decompressionFailed,

  /// A valid gzip stream that expands past what a producer is allowed to seal.
  ///
  /// Not the same as [decompressionFailed]: the stream is fine, and that is the
  /// problem. gzip reaches roughly 1000:1, so a few megabytes expands to
  /// gigabytes — and an artifact is immutable and sorts newest, so the same
  /// bomb would be chosen again on every sync. The one failure here that is
  /// not self-limiting unless it is caught.
  decompressedTooLarge,

  /// Bytes that cannot be an ANS-104 data item at all.
  malformedFrame,

  /// Signed by a wallet that is not the drive's owner. The signature may be
  /// perfectly valid; it is simply not the owner's.
  ownerMismatch,

  /// The signature does not verify: these are not the bytes the owner signed.
  signatureInvalid,
}

class ArtifactSealException implements Exception {
  final ArtifactSealFailure reason;
  final String detail;
  ArtifactSealException(this.reason, this.detail);
  @override
  String toString() => 'ArtifactSealException($reason): $detail';
}

/// A sealed artifact, with the tag values needed to read it back off chain.
///
/// Cipher-presence is the discriminator: a private drive's artifact carries
/// `Cipher` and `Cipher-IV`, a public drive's carries neither. There is no
/// third state, and the two constructors are the only ways to build one.
class SealedArtifact {
  final Uint8List body;
  final String? cipher;
  final String? cipherIv;

  const SealedArtifact._(this.body, this.cipher, this.cipherIv);

  const SealedArtifact.public(Uint8List body) : this._(body, null, null);

  const SealedArtifact.private(
    Uint8List body, {
    required String cipher,
    required String cipherIv,
  }) : this._(body, cipher, cipherIv);

  bool get isEncrypted => cipher != null;
}

/// Compresses [artifactBytes], hands them to [signPayload] to be signed as a
/// data item, and — when [driveKey] is given — encrypts the signed frame.
///
/// [signPayload] is a collaborator rather than a direct call so that this stays
/// testable without a wallet, and so the CLI can supply its own signer.
Future<SealedArtifact> sealArtifact(
  Uint8List artifactBytes, {
  required Future<Uint8List> Function(Uint8List gzipped) signPayload,
  SecretKey? driveKey,
}) async {
  final gzipped = Uint8List.fromList(
    GZipEncoder().encode(artifactBytes, level: 6)!,
  );

  final signed = await signPayload(gzipped);

  if (driveKey == null) return SealedArtifact.public(signed);

  final impl = cipherBufferImpl(Cipher.aes256gcm);
  final encrypted = await impl.encrypt(signed, secretKey: driveKey);

  return SealedArtifact.private(
    // Ciphertext and MAC concatenated, matching every other encrypted body
    // this app writes.
    Uint8List.fromList(encrypted.concatenation(nonce: false)),
    cipher: Cipher.aes256gcm,
    cipherIv:
        arweave_utils.encodeBytesToBase64(Uint8List.fromList(encrypted.nonce)),
  );
}

/// The inverse: decrypt if encrypted, verify the owner's signature, inflate.
///
/// [verifyAndUnwrap] returns the payload the owner signed, or throws with an
/// [ArtifactSealFailure] if the frame is malformed, the signer is not
/// [expectedOwner], or the signature does not verify.
///
/// [maxPlaintextBytes] bounds the inflation, and it is applied **during**
/// inflation rather than after. A reader that inflates into memory and checks
/// the size afterwards has already lost, and the gzip trailer's `ISIZE` is not
/// the bound either — it is chosen by whoever wrote the stream.
Future<Uint8List> openArtifact(
  Uint8List body, {
  required bool driveIsPrivate,
  required String? cipher,
  required String? cipherIv,
  required Future<Uint8List> Function(Uint8List frame, String expectedOwner)
      verifyAndUnwrap,
  required String expectedOwner,
  required int maxPlaintextBytes,
  SecretKey? driveKey,
}) async {
  if (driveIsPrivate != (cipher != null)) {
    throw ArtifactSealException(
      ArtifactSealFailure.privacyMismatch,
      driveIsPrivate ? 'private drive, no cipher' : 'public drive, cipher',
    );
  }
  if (cipher != null && cipher != Cipher.aes256gcm) {
    throw ArtifactSealException(ArtifactSealFailure.unsupportedCipher, cipher);
  }

  var frame = body;
  if (cipher != null) {
    if (driveKey == null || cipherIv == null) {
      throw ArtifactSealException(
        ArtifactSealFailure.decryptionFailed,
        driveKey == null ? 'no drive key' : 'no cipher IV',
      );
    }
    frame = await _decrypt(body, cipherIv, driveKey);
  }

  // Signature first: nothing is inflated until the owner's signature over
  // these exact bytes has verified.
  final payload = await verifyAndUnwrap(frame, expectedOwner);

  return _inflateBounded(payload, maxPlaintextBytes);
}

Future<Uint8List> _decrypt(
  Uint8List body,
  String cipherIv,
  SecretKey driveKey,
) async {
  try {
    final impl = cipherBufferImpl(Cipher.aes256gcm);
    final nonce = arweave_utils.decodeBase64ToBytes(cipherIv);
    // The body is ciphertext followed by the MAC, the same concatenation
    // `sealArtifact` wrote and every other encrypted body in this app uses.
    final macLength = impl.macAlgorithm.macLength;
    if (body.length < macLength) {
      throw ArtifactSealException(
        ArtifactSealFailure.decryptionFailed,
        'body shorter than a MAC',
      );
    }
    final box = SecretBox(
      body.sublist(0, body.length - macLength),
      nonce: nonce,
      mac: Mac(body.sublist(body.length - macLength)),
    );
    return Uint8List.fromList(await impl.decrypt(box, secretKey: driveKey));
  } on ArtifactSealException {
    rethrow;
  } catch (e) {
    throw ArtifactSealException(ArtifactSealFailure.decryptionFailed, '$e');
  }
}

Uint8List _inflateBounded(Uint8List gzipped, int maxBytes) {
  final List<int> out;
  try {
    out = GZipDecoder().decodeBytes(gzipped, verify: true);
  } catch (e) {
    throw ArtifactSealException(
      ArtifactSealFailure.decompressionFailed,
      '$e',
    );
  }
  if (out.length > maxBytes) {
    throw ArtifactSealException(
      ArtifactSealFailure.decompressedTooLarge,
      '${out.length} bytes expands past $maxBytes',
    );
  }
  return Uint8List.fromList(out);
}

/// The tags a sealed artifact is published under.
Map<String, String> tagsFor(
  SealedArtifact sealed, {
  required String driveId,
  required String driveStateId,
  required int blockStart,
  required int blockEnd,
  required int entityCount,
  required DateTime unixTime,
}) =>
    driveStateTags(
      driveId: driveId,
      driveStateId: driveStateId,
      blockStart: blockStart,
      blockEnd: blockEnd,
      entityCount: entityCount,
      unixTime: unixTime,
      cipher: sealed.cipher,
      cipherIv: sealed.cipherIv,
    );
