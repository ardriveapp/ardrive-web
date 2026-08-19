import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart' show ArDriveCrypto;
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' show SecretKey;

/// Why a drive state artifact could not be produced, or could not be opened.
///
/// Every one of these is a **fallback and not an error**: the caller logs the
/// reason and syncs the ordinary way, because no drive may ever fail because
/// an artifact was bad (`docs/drive-state/DECISIONS.md`, non-negotiable 2).
/// Enumerating them is what lets that log answer *why* a drive did not use its
/// artifact, without a stack trace and without guessing.
enum DriveStateEnvelopeFailure {
  /// The plaintext is at or above [maxSizeSupportedByGCMEncryption].
  ///
  /// D5: refuse, with a reason. Never fall through to AES-CTR, which is
  /// unauthenticated (proposal 2.3), and never split — multi-part
  /// authentication needs a manifest integrity design that does not exist yet.
  plaintextTooLarge,

  /// The owner's wallet did not produce a signature.
  signingFailed,

  /// gzip produced nothing for a payload it was given.
  compressionFailed,

  /// The `Cipher` tag names something other than AES256-GCM. Reading one of
  /// those would mean trusting unauthenticated bytes, which is the whole thing
  /// this format refuses to do (proposal 2.3).
  unsupportedCipher,

  /// The body did not decrypt under the drive key.
  ///
  /// GCM cannot tell a wrong key from wrong bytes, and it does not have to:
  /// both mean this artifact is not usable. Gateways have been observed
  /// serving bodies that arrived wrong; this is the check that catches them.
  decryptionFailed,

  /// The decrypted bytes are not a gzip stream.
  decompressionFailed,

  /// The decompressed bytes are not a drive state frame, or the frame's own
  /// lengths do not add up.
  malformedFrame,

  /// The frame is a version of the container format this client does not know.
  unsupportedFrameVersion,

  /// The frame is signed with a scheme this client cannot verify.
  unsupportedSignatureType,

  /// The frame is signed by a wallet that is not the drive's owner. The
  /// signature may well be valid — it is simply not the owner's.
  ownerMismatch,

  /// The signature does not verify: these are not the bytes the owner signed.
  signatureInvalid,
}

/// A sealed artifact body, together with the two tag values needed to read it
/// back off chain.
class DriveStateEnvelope {
  /// The AES-GCM ciphertext with its MAC appended — the transaction's data.
  ///
  /// The concatenation (ciphertext then MAC, nonce carried separately in a
  /// tag) is this codebase's long-standing convention; see
  /// [ArDriveCrypto.secretBoxFromDataWithMacConcatenation].
  final Uint8List body;

  /// The 12 byte GCM nonce. Travels in the `Cipher-IV` tag, base64.
  final Uint8List cipherIv;

  /// The `Cipher` tag. Always [Cipher.aes256gcm] for anything sealed here.
  final String cipher;

  const DriveStateEnvelope({
    required this.body,
    required this.cipherIv,
    this.cipher = Cipher.aes256gcm,
  });

  String get cipherIvAsBase64 => utils.encodeBytesToBase64(cipherIv);
}

/// The outcome of sealing an artifact body: an envelope, or a typed refusal.
class DriveStateSealResult {
  /// The sealed body. `null` when the codec refused.
  final DriveStateEnvelope? envelope;

  /// Why the codec refused. `null` when [isSealed].
  final DriveStateEnvelopeFailure? failure;

  /// Detail for the log, never for the user. `null` when [isSealed].
  final String? reason;

  const DriveStateSealResult._(this.envelope, this.failure, this.reason);

  const DriveStateSealResult.sealed(DriveStateEnvelope envelope)
      : this._(envelope, null, null);

  const DriveStateSealResult.refused(
    DriveStateEnvelopeFailure failure,
    String reason,
  ) : this._(null, failure, reason);

  bool get isSealed => envelope != null;
  bool get isRefused => failure != null;

  @override
  String toString() => isSealed
      ? 'DriveStateSealResult(sealed, ${envelope!.body.length} bytes)'
      : 'DriveStateSealResult(${failure!.name}, $reason)';
}

/// The outcome of opening an artifact body: the plaintext the owner signed, or
/// a typed reason it could not be trusted.
class DriveStateOpenResult {
  /// The verified plaintext, byte for byte as it was handed to
  /// [DriveStateEnvelopeCodec.seal]. `null` when the artifact was rejected.
  final Uint8List? plaintext;

  /// The address that signed [plaintext]. `null` when the artifact was
  /// rejected. Always equal to the expected owner address when set — it is
  /// returned so a caller can log what it verified rather than what it asked
  /// for.
  final String? ownerAddress;

  /// Why the artifact was rejected. `null` when [isOpened].
  final DriveStateEnvelopeFailure? failure;

  /// Detail for the log, never for the user. `null` when [isOpened].
  final String? reason;

  const DriveStateOpenResult._(
    this.plaintext,
    this.ownerAddress,
    this.failure,
    this.reason,
  );

  const DriveStateOpenResult.opened(
    Uint8List plaintext,
    String ownerAddress,
  ) : this._(plaintext, ownerAddress, null, null);

  const DriveStateOpenResult.failed(
    DriveStateEnvelopeFailure failure,
    String reason,
  ) : this._(null, null, failure, reason);

  bool get isOpened => plaintext != null;
  bool get isFailed => failure != null;

  @override
  String toString() => isOpened
      ? 'DriveStateOpenResult(opened, ${plaintext!.length} bytes, '
          'signed by $ownerAddress)'
      : 'DriveStateOpenResult(${failure!.name}, $reason)';
}

/// Seals a drive state payload into the body of an ArFS `drive-state` entity,
/// and opens one again.
///
/// The order of operations is the format, and it is not negotiable
/// (proposal 2.2 and 3.3):
///
/// ```
/// serialise  ->  sign (owner wallet)  ->  gzip  ->  AES256-GCM
/// ```
///
/// Signing the *plaintext* binds the owner to the content rather than to a
/// particular encoding, so an artifact verifies the same whether it arrived as
/// a top level transaction or as a bundled data item — the latter has no L1
/// header, so its owner is otherwise knowable only through a GraphQL indexer.
/// Compressing before encrypting is the only order that compresses at all.
///
/// Opening runs the exact inverse, and rejects rather than throws. Serialising
/// the payload is not this codec's job: it is handed bytes and hands bytes
/// back.
///
/// ## The frame
///
/// The signature has to travel with the payload it covers, so the compressed,
/// encrypted body is a small self-describing frame rather than the payload
/// alone. All integers are big-endian, and none is 64 bit — `ByteData` has no
/// `getUint64` on the web.
///
/// ```
/// offset  size  field
///      0     8  magic, ASCII "ARDRVSTA"
///      8     2  frame version, uint16
///     10     2  signature type, as ANS-104 numbers them (1 = Arweave)
///     12     4  owner length, uint32
///     16     4  signature length, uint32
///     20     4  payload length, uint32
///     24     n  owner (the signing wallet's public key)
///      .     n  signature over the payload
///      .     n  payload  <- always last, and always to the end of the frame
/// ```
///
/// The owner travels in the frame because verification must not depend on how
/// the artifact was found. The address is derived from it and checked against
/// the drive's known owner, so carrying it grants nothing: a frame naming a
/// different key is rejected before its signature is even examined.
///
/// The payload is signed exactly as given, with no domain separator of this
/// codec's own. The container it carries names its own type and version
/// (D1), which is where a reader learns what it is looking at.
class DriveStateEnvelopeCodec {
  final ArDriveCrypto _crypto;

  DriveStateEnvelopeCodec({ArDriveCrypto? crypto})
      : _crypto = crypto ?? ArDriveCrypto();

  /// The version of the frame layout this codec writes.
  static const int frameVersion = 1;

  /// The frame's first eight bytes.
  static final Uint8List magic = ascii.encode('ARDRVSTA');

  static const int _headerLength = 24;

  /// Passed to the wallet so a signing prompt, and our own logs, can say what
  /// is being signed.
  static const String _signContext = 'drive-state';

  /// Signs [plaintext] with [wallet], compresses it, and encrypts it under
  /// [driveKey].
  ///
  /// Refuses, rather than throws, when the payload is too large for AES-GCM or
  /// the wallet will not sign.
  Future<DriveStateSealResult> seal({
    required Uint8List plaintext,
    required SecretKey driveKey,
    required Wallet wallet,
  }) async {
    // D5. The boundary is the one the uploader uses to choose GCM over CTR
    // (`fileLength < maxSizeSupportedByGCMEncryption`), so a payload sitting
    // exactly on it is already CTR territory elsewhere and is refused here.
    if (plaintext.lengthInBytes >= maxSizeSupportedByGCMEncryption) {
      return DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.plaintextTooLarge,
        '${plaintext.lengthInBytes} bytes is at or above the '
        '$maxSizeSupportedByGCMEncryption byte AES-GCM boundary; '
        'a drive this large falls back to snapshots',
      );
    }

    final String owner;
    final Uint8List signature;
    try {
      owner = await wallet.getOwner();
      signature = await wallet.sign(plaintext, _signContext);
    } catch (e) {
      return DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.signingFailed,
        'The owner wallet did not sign the payload: $e',
      );
    }

    final Uint8List ownerKey;
    try {
      ownerKey = utils.decodeBase64ToBytes(owner);
    } catch (e) {
      return DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.signingFailed,
        'The owner wallet did not return a readable public key: $e',
      );
    }

    final frame = _buildFrame(
      owner: ownerKey,
      signature: signature,
      payload: plaintext,
    );

    final compressed = GZipEncoder().encode(frame);
    if (compressed == null) {
      return const DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.compressionFailed,
        'gzip returned nothing for the signed frame',
      );
    }

    final secretBox = await _crypto.encrypt(
      compressed is Uint8List ? compressed : Uint8List.fromList(compressed),
      driveKey,
    );

    return DriveStateSealResult.sealed(
      DriveStateEnvelope(
        // Ciphertext then MAC; the nonce goes in the Cipher-IV tag.
        body: secretBox.concatenation(nonce: false),
        cipherIv: Uint8List.fromList(secretBox.nonce),
      ),
    );
  }

  /// Decrypts [envelope] under [driveKey], decompresses it, and returns the
  /// payload only if it was signed by [expectedOwnerAddress].
  ///
  /// Never throws: every way this can go wrong is a
  /// [DriveStateEnvelopeFailure] the caller logs before falling back.
  Future<DriveStateOpenResult> open({
    required DriveStateEnvelope envelope,
    required SecretKey driveKey,
    required String expectedOwnerAddress,
  }) async {
    if (envelope.cipher != Cipher.aes256gcm) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.unsupportedCipher,
        'Drive state artifacts are AES256-GCM only, and this one declares '
        '${envelope.cipher}',
      );
    }

    if (expectedOwnerAddress.isEmpty) {
      return const DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.ownerMismatch,
        'No expected owner address to verify against',
      );
    }

    final Uint8List compressed;
    try {
      compressed = await _crypto.decrypt(
        envelope.body,
        driveKey,
        envelope.cipherIv,
      );
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.decryptionFailed,
        'The body did not decrypt under the drive key: $e',
      );
    }

    final List<int> framed;
    try {
      framed = GZipDecoder().decodeBytes(compressed);
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.decompressionFailed,
        'The decrypted body is not a gzip stream: $e',
      );
    }

    final _Frame frame;
    try {
      frame = _readFrame(
        framed is Uint8List ? framed : Uint8List.fromList(framed),
      );
    } on _FrameRejected catch (e) {
      return DriveStateOpenResult.failed(e.failure, e.reason);
    }

    final owner = utils.encodeBytesToBase64(frame.owner);

    // The address is checked before the signature deliberately. It is the
    // cheap half of the question, and it is the half that distinguishes "not
    // the owner's artifact" from "the owner's artifact, damaged" in the log.
    final String signerAddress;
    try {
      signerAddress = await utils.ownerToAddress(owner);
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        'The frame does not carry a readable owner key: $e',
      );
    }

    if (signerAddress != expectedOwnerAddress) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.ownerMismatch,
        'Signed by $signerAddress, but the drive is owned by '
        '$expectedOwnerAddress',
      );
    }

    final bool verified;
    try {
      verified = await SignatureConfig.arweave.verify(
        frame.payload,
        frame.signature,
        owner,
      );
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.signatureInvalid,
        'The signature could not be checked: $e',
      );
    }

    if (!verified) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.signatureInvalid,
        'The payload is not what $signerAddress signed',
      );
    }

    return DriveStateOpenResult.opened(frame.payload, signerAddress);
  }

  Uint8List _buildFrame({
    required Uint8List owner,
    required Uint8List signature,
    required Uint8List payload,
  }) {
    final frame = Uint8List(
      _headerLength + owner.length + signature.length + payload.length,
    );
    final header = ByteData.sublistView(frame, 0, _headerLength);

    frame.setRange(0, magic.length, magic);
    header.setUint16(8, frameVersion);
    header.setUint16(10, SignatureConfig.arweave.signatureType);
    header.setUint32(12, owner.length);
    header.setUint32(16, signature.length);
    header.setUint32(20, payload.length);

    var offset = _headerLength;
    frame.setRange(offset, offset + owner.length, owner);
    offset += owner.length;
    frame.setRange(offset, offset + signature.length, signature);
    offset += signature.length;
    frame.setRange(offset, offset + payload.length, payload);

    return frame;
  }

  _Frame _readFrame(Uint8List framed) {
    if (framed.length < _headerLength) {
      throw _FrameRejected(
        DriveStateEnvelopeFailure.malformedFrame,
        '${framed.length} bytes is shorter than the $_headerLength byte '
        'frame header',
      );
    }

    for (var i = 0; i < magic.length; i++) {
      if (framed[i] != magic[i]) {
        throw const _FrameRejected(
          DriveStateEnvelopeFailure.malformedFrame,
          'The decompressed body does not start with a drive state frame',
        );
      }
    }

    final header = ByteData.sublistView(framed, 0, _headerLength);
    final version = header.getUint16(8);
    if (version != frameVersion) {
      throw _FrameRejected(
        DriveStateEnvelopeFailure.unsupportedFrameVersion,
        'Frame version $version, but this client writes $frameVersion',
      );
    }

    final signatureType = header.getUint16(10);
    if (signatureType != SignatureConfig.arweave.signatureType) {
      throw _FrameRejected(
        DriveStateEnvelopeFailure.unsupportedSignatureType,
        'Signature type $signatureType cannot be verified by this client',
      );
    }

    final ownerLength = header.getUint32(12);
    final signatureLength = header.getUint32(16);
    final payloadLength = header.getUint32(20);

    if (ownerLength != SignatureConfig.arweave.publicKeyLength ||
        signatureLength != SignatureConfig.arweave.signatureLength) {
      throw _FrameRejected(
        DriveStateEnvelopeFailure.malformedFrame,
        'An Arweave signed frame carries a '
        '${SignatureConfig.arweave.publicKeyLength} byte owner and a '
        '${SignatureConfig.arweave.signatureLength} byte signature, not '
        '$ownerLength and $signatureLength',
      );
    }

    final expectedLength =
        _headerLength + ownerLength + signatureLength + payloadLength;
    if (framed.length != expectedLength) {
      throw _FrameRejected(
        DriveStateEnvelopeFailure.malformedFrame,
        'The frame declares $expectedLength bytes but is ${framed.length}',
      );
    }

    var offset = _headerLength;
    final owner = Uint8List.sublistView(framed, offset, offset + ownerLength);
    offset += ownerLength;
    final signature =
        Uint8List.sublistView(framed, offset, offset + signatureLength);
    offset += signatureLength;
    final payload =
        Uint8List.sublistView(framed, offset, offset + payloadLength);

    return _Frame(owner: owner, signature: signature, payload: payload);
  }
}

class _Frame {
  final Uint8List owner;
  final Uint8List signature;
  final Uint8List payload;

  const _Frame({
    required this.owner,
    required this.signature,
    required this.payload,
  });
}

/// Thrown only inside [DriveStateEnvelopeCodec._readFrame], and turned into a
/// [DriveStateOpenResult] before it can escape.
class _FrameRejected implements Exception {
  final DriveStateEnvelopeFailure failure;
  final String reason;

  const _FrameRejected(this.failure, this.reason);
}
