import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart' show ArDriveCrypto;
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' show SecretKey, Sha256;

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

  /// The owner's wallet did not produce a signed data item.
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

  /// The signed data item's data is not a gzip stream.
  decompressionFailed,

  /// The decrypted bytes cannot be an ANS-104 data item at all: too short to
  /// hold one, or carrying an owner key that cannot be read back out. Bytes
  /// that are the right shape but do not verify are [signatureInvalid], not
  /// this.
  malformedFrame,

  /// The data item is signed with a scheme this client cannot verify. ANS-104
  /// numbers these in the first two bytes of an item; only 1 (Arweave) can be
  /// checked here.
  unsupportedSignatureType,

  /// The data item is signed by a wallet that is not the drive's owner. The
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
/// ```
/// serialise  ->  gzip  ->  sign (ANS-104 data item)  ->  AES256-GCM
/// ```
///
/// ## Why a data item, and not a bare signature
///
/// The owner's signature has to travel *inside* the artifact. A reader that
/// fetches `GET https://gateway/<txid>` receives the data and nothing else,
/// and `GET /tx/<id>` is a 404 for anything that arrived bundled — so an
/// artifact whose authorship lived in the L1 header could only be attributed
/// through a GraphQL indexer, which this design will not depend on
/// (`docs/DRIVE_STATE_ARTIFACT.md` §4.2).
///
/// The carrier for that signature is an ANS-104 data item, signed through the
/// same seam every ArDrive upload already uses: [DataItem.sign] with an
/// [ArweaveSigner], the shape of `ArweaveService.prepareBundledDataItem` and
/// `BDISigner`. That choice is not decoration. ArConnect and Wander have
/// deprecated arbitrary-data signing, so a codec that called `wallet.sign` on
/// a payload of its own devising would never produce an artifact at all for an
/// extension user, while data item signing is the one path those wallets still
/// grant.
///
/// Being a real data item rather than a bespoke frame also means the bytes are
/// checkable by anything that speaks ANS-104, and that the parsing and the
/// verification are the package's rather than ours.
///
/// ## Why gzip is inside the signature
///
/// The item's data is the *compressed* payload, so the signature covers the
/// bytes a reader is holding before it has decompressed anything. Authorship
/// is settled before any of the payload is expanded, and a body the owner did
/// not sign never reaches the decompressor at all. Compressing before
/// encrypting remains the only order that compresses.
///
/// The item carries no tags, no target and no anchor: the ArFS tags that make
/// an artifact discoverable live on the enclosing transaction, and the less
/// this signature covers beyond the payload, the fewer ways there are for the
/// two to disagree.
///
/// Opening runs the exact inverse — decrypt, parse and verify the data item,
/// confirm the signer is the drive's owner, decompress — and rejects rather
/// than throws. Serialising the payload is not this codec's job: it is handed
/// bytes and hands bytes back.
class DriveStateEnvelopeCodec {
  final ArDriveCrypto _crypto;

  DriveStateEnvelopeCodec({ArDriveCrypto? crypto})
      : _crypto = crypto ?? ArDriveCrypto();

  /// The only ANS-104 signature scheme this codec writes, and the only one it
  /// can check: every other [SignatureConfig] in the package throws
  /// `UnimplementedError` out of its verifier.
  static final SignatureConfig _signatureConfig = SignatureConfig.arweave;

  /// The ANS-104 signature type field: the first two bytes of a data item,
  /// little endian.
  static const int _signatureTypeLength = 2;

  /// The shortest run of bytes that could be an Arweave signed data item:
  /// signature type, signature, owner, an absent target and anchor, and the
  /// two eight byte tag counts. Anything below this is not a small data item,
  /// it is not a data item.
  static final int _minimumDataItemLength = _signatureTypeLength +
      _signatureConfig.signatureLength +
      _signatureConfig.publicKeyLength +
      1 + // target present flag
      1 + // anchor present flag
      8 + // number of tags
      8; // number of tag bytes

  /// Compresses [plaintext], signs it with [wallet] as an ANS-104 data item,
  /// and encrypts that item under [driveKey].
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

    final compressed = GZipEncoder().encode(plaintext);
    if (compressed == null) {
      return const DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.compressionFailed,
        'gzip returned nothing for the payload',
      );
    }

    final Uint8List signedItem;
    try {
      final item = DataItem.withBlobData(data: _asBytes(compressed))
        ..setOwner(await wallet.getOwner());

      // The upload path's seam, unchanged: a data item signature, which is
      // what ArConnect and Wander still grant, rather than arbitrary bytes,
      // which they no longer do.
      await item.sign(ArweaveSigner(wallet));

      signedItem = (await item.asBinary()).takeBytes();
    } catch (e) {
      return DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.signingFailed,
        'The owner wallet did not sign a data item for the payload: $e',
      );
    }

    final secretBox = await _crypto.encrypt(signedItem, driveKey);

    return DriveStateSealResult.sealed(
      DriveStateEnvelope(
        // Ciphertext then MAC; the nonce goes in the Cipher-IV tag.
        body: secretBox.concatenation(nonce: false),
        cipherIv: Uint8List.fromList(secretBox.nonce),
      ),
    );
  }

  /// Decrypts [envelope] under [driveKey] and returns its payload only if the
  /// data item inside verifies and was signed by [expectedOwnerAddress].
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

    final Uint8List binary;
    try {
      binary = await _crypto.decrypt(
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

    if (binary.lengthInBytes < _minimumDataItemLength) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        '${binary.lengthInBytes} bytes cannot hold an ANS-104 data item, '
        'which is at least $_minimumDataItemLength',
      );
    }

    // Read before parsing, because the signature type is what says how long
    // the signature and owner fields are. Handing the parser a config that
    // disagrees would not fail loudly; it would read the item at the wrong
    // offsets.
    final signatureType = _readSignatureType(binary);
    if (signatureType != _signatureConfig.signatureType) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.unsupportedSignatureType,
        'Signature type $signatureType cannot be verified by this client',
      );
    }

    final ProcessedDataItem item;
    try {
      // Parses the item and checks its signature in one pass, throwing when
      // the signature does not verify. Nothing downstream of here is reached
      // by bytes nobody signed.
      item = await processDataItem(
        dataItemStreamGenerator: () => Stream.value(binary),
        id: await _idOf(binary),
        length: binary.lengthInBytes,
        signatureConfig: _signatureConfig,
      );
    } catch (e) {
      // Everything this can throw past the checks above says the same thing:
      // whatever these bytes are, the owner did not sign them. That covers a
      // signature that verifies to false, and equally a structure that never
      // got far enough to be checked — RSA-PSS verification raises an `Error`
      // rather than returning false on a signature it cannot even decode, so
      // there is no honest line to draw between "damaged" and "unsigned"
      // here, and drawing one on exception messages would be worse than not
      // drawing it. The structural failures this codec *can* name for the log
      // are the two checks above, which run first for exactly that reason.
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.signatureInvalid,
        'The data item does not carry a valid owner signature over these '
        'bytes: $e',
      );
    }

    final String signerAddress;
    try {
      signerAddress = await utils.ownerToAddress(item.owner);
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        'The data item does not carry a readable owner key: $e',
      );
    }

    // The signature has already been checked by this point, so a mismatch
    // here means exactly one thing and the log can say it: somebody else's
    // perfectly valid artifact.
    if (signerAddress != expectedOwnerAddress) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.ownerMismatch,
        'Signed by $signerAddress, but the drive is owned by '
        '$expectedOwnerAddress',
      );
    }

    final Uint8List compressed;
    try {
      compressed = await _collect(item.dataStreamGenerator);
    } on Error catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        'The data item\'s data could not be read back: $e',
      );
    }

    final List<int> plaintext;
    try {
      plaintext = GZipDecoder().decodeBytes(compressed);
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.decompressionFailed,
        'The signed data is not a gzip stream: $e',
      );
    }

    return DriveStateOpenResult.opened(_asBytes(plaintext), signerAddress);
  }

  /// The ANS-104 signature type: two bytes, little endian, at offset zero.
  int _readSignatureType(Uint8List binary) => utils.byteArrayToLong(
        Uint8List.sublistView(binary, 0, _signatureTypeLength),
      );

  /// A data item's id is *defined* as the SHA-256 of its signature, so it is
  /// derived here rather than carried alongside: there is no bundle header to
  /// read one out of, and a value stored next to the body would be a value an
  /// attacker could choose. [processDataItem] asks for it so it can reject
  /// items whose bundle header and body disagree, a check that does not apply
  /// to an item travelling alone — the authorship question is settled by the
  /// signature check that follows it, not by this.
  Future<String> _idOf(Uint8List binary) async {
    final signature = Uint8List.sublistView(
      binary,
      _signatureTypeLength,
      _signatureTypeLength + _signatureConfig.signatureLength,
    );

    return utils.encodeBytesToBase64((await Sha256().hash(signature)).bytes);
  }

  Future<Uint8List> _collect(DataStreamGenerator generator) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in generator()) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static Uint8List _asBytes(List<int> bytes) =>
      bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
}
