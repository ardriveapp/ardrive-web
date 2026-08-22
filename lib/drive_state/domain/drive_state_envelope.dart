import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart' show ArDriveCrypto;
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/foundation.dart' show visibleForTesting;

/// Why a drive state artifact could not be produced, or could not be opened.
///
/// Every one of these is a **fallback and not an error**: the caller logs the
/// reason and syncs the ordinary way, because no drive may ever fail because
/// an artifact was bad (`docs/drive-state/DECISIONS.md`, non-negotiable 2).
/// Enumerating them is what lets that log answer *why* a drive did not use its
/// artifact, without a stack trace and without guessing.
enum DriveStateEnvelopeFailure {
  /// The payload is at or above
  /// [DriveStateEnvelopeCodec.defaultMaxPlaintextBytes].
  ///
  /// D5: refuse, with a reason, rather than split. The bound is on the
  /// **producer's memory**, not on the cipher — see that constant — so it
  /// applies to a public drive's artifact exactly as it does to a private
  /// one, even though nothing in the public path is encrypted at all.
  plaintextTooLarge,

  /// The owner's wallet did not produce a signed data item.
  signingFailed,

  /// gzip produced nothing for a payload it was given.
  compressionFailed,

  /// The `Cipher` tag names something other than AES256-GCM. Reading one of
  /// those would mean trusting unauthenticated bytes, which is the whole thing
  /// this format refuses to do (proposal 2.3).
  unsupportedCipher,

  /// The drive is **private** and the artifact declares no cipher.
  ///
  /// One direction of the cipher/privacy cross-check (§2.6). No client of this
  /// format may publish a private drive in the clear — [DriveStateProtection]
  /// makes that value unconstructable — so an artifact that did was written by
  /// something else, or by a client with that rail broken. Either way it is
  /// not a format this reader agreed to, and accepting it would normalise the
  /// one publication that can never be taken back.
  ///
  /// Refused before the bytes are looked at, so a plaintext body for a private
  /// drive is never parsed, never inflated and never merged.
  plaintextForPrivateDrive,

  /// The drive is **public** and the artifact declares a cipher.
  ///
  /// The other direction. A public drive has no key, so there is nothing to
  /// decrypt this with and no honest way to read it. Naming the contradiction
  /// is better than the `decryptionFailed` a reader would otherwise report for
  /// a key it never had.
  ciphertextForPublicDrive,

  /// The body did not decrypt under the drive key.
  ///
  /// GCM cannot tell a wrong key from wrong bytes, and it does not have to:
  /// both mean this artifact is not usable. Gateways have been observed
  /// serving bodies that arrived wrong; this is the check that catches them.
  decryptionFailed,

  /// The signed data item's data is not a gzip stream.
  decompressionFailed,

  /// The signed data is a gzip stream that expands past
  /// [DriveStateEnvelopeCodec.maxPlaintextBytes].
  ///
  /// Not the same thing as [decompressionFailed]: the stream is valid, and
  /// that is the problem. gzip reaches about 1032:1, so an artifact of a few
  /// megabytes — well under anything a size check on the body would catch —
  /// expands to gigabytes. Verification cannot help, because the owner really
  /// did sign it, or the bytes are the owner's own and somebody re-published
  /// them; a browser tab has no memory pressure signal to recover from, it
  /// simply dies. And an artifact is immutable and sorts newest, so the same
  /// bomb would be chosen again on the next sync, and the next: the one shape
  /// of failure that is not a fallback unless it is caught here.
  decompressedTooLarge,

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

/// The shape of [processDataItem], so that [DriveStateEnvelopeCodec] can take
/// it as a collaborator. See [DriveStateEnvelopeCodec._parseDataItem] for why
/// it is a collaborator at all.
typedef DriveStateDataItemParser = Future<ProcessedDataItem> Function({
  required DataStreamGenerator dataItemStreamGenerator,
  required String id,
  required int length,
  required SignatureConfig signatureConfig,
});

/// A sealed artifact body, together with the tag values needed to read it back
/// off chain.
///
/// **Cipher-presence is the discriminator.** A private drive's artifact
/// carries `Cipher` and `Cipher-IV`; a public drive's carries neither, because
/// there is no key and nothing was encrypted. The two named constructors are
/// the only ways to build one, so an envelope can never hold a cipher without
/// its IV, or an IV without its cipher — the shape a reader would have to
/// guess at.
class DriveStateEnvelope {
  /// The transaction's data.
  ///
  /// For a private drive: the AES-GCM ciphertext with its MAC appended. The
  /// concatenation (ciphertext then MAC, nonce carried separately in a tag) is
  /// this codebase's long-standing convention; see
  /// [ArDriveCrypto.secretBoxFromDataWithMacConcatenation].
  ///
  /// For a public drive: the signed ANS-104 data item itself, with no
  /// encryption layer around it.
  final Uint8List body;

  /// The 12 byte GCM nonce, travelling in the `Cipher-IV` tag as base64.
  /// `null` for a public drive's artifact, which has no cipher to nonce.
  final Uint8List? cipherIv;

  /// The `Cipher` tag. [Cipher.aes256gcm] for anything this codec seals for a
  /// private drive, and `null` for a public one.
  ///
  /// Nullable rather than defaulted, because its absence is load-bearing: a
  /// reader cross-checks it against the privacy of the drive the artifact
  /// claims to be for, in both directions.
  final String? cipher;

  const DriveStateEnvelope._(this.body, this.cipher, this.cipherIv);

  /// A private drive's artifact.
  ///
  /// [cipher] is named rather than assumed so the importer can hand over
  /// whatever the `Cipher` tag actually said and have the codec refuse it;
  /// a producer leaves it at [Cipher.aes256gcm].
  const DriveStateEnvelope.encrypted({
    required Uint8List body,
    required Uint8List cipherIv,
    String cipher = Cipher.aes256gcm,
  }) : this._(body, cipher, cipherIv);

  /// A public drive's artifact: signed, and not encrypted.
  ///
  /// There is no cipher parameter and no IV parameter, which is the point.
  const DriveStateEnvelope.inTheClear({required Uint8List body})
      : this._(body, null, null);

  /// Whether this artifact carries a cipher at all. The discriminator a reader
  /// checks against the drive's privacy.
  bool get isEncrypted => cipher != null;

  /// The `Cipher-IV` tag value, or `null` when there is no cipher to tag.
  String? get cipherIvAsBase64 =>
      cipherIv == null ? null : utils.encodeBytesToBase64(cipherIv!);
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
/// private:  serialise  ->  gzip  ->  sign (ANS-104 data item)  ->  AES256-GCM
/// public:   serialise  ->  gzip  ->  sign (ANS-104 data item)
/// ```
///
/// ## The public path is the same chain minus one layer
///
/// A public drive has no drive key, so there is nothing to encrypt with and
/// nothing worth hiding: its contents are already readable by anyone, and a
/// snapshot of a public drive is already the same enumeration of every name,
/// size and relationship, unencrypted, published today (§2.6). What a public
/// drive still gets is the expensive half — the ~420 GraphQL queries and
/// ~42,000 metadata fetches an artifact replaces (§1.2) — of which the
/// per-entity decryption it skips is a small fraction.
///
/// Which path runs is decided by [DriveStateProtection] and nothing else. The
/// plaintext variant cannot be constructed for a private drive, so this codec
/// has no branch, flag or argument that could publish one in the clear.
///
/// **The signature matters more here, not less.** Without a key it is the only
/// thing binding a public artifact to the drive's owner: anyone can post bytes
/// tagged with a `Drive-Id`, and for a private drive the drive key is a second
/// filter that a public drive does not have. Every check below the signature
/// runs identically on both paths.
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
/// What signing before compressing does *not* buy is any protection from the
/// decompressor: a verified signature says the owner produced these bytes, not
/// that they are safe to expand. Anyone can re-publish the owner's own bytes
/// verbatim, so the bomb described by
/// [DriveStateEnvelopeFailure.decompressedTooLarge] reaches the decompressor
/// by design. [maxPlaintextBytes] is what stops it, and it is the same
/// boundary [seal] refuses to cross in the other direction.
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

  /// The signature-checking ANS-104 parse [open] runs.
  ///
  /// Injectable only so a test can hand back an item whose data stream fails,
  /// which is the one branch of [open]'s "never throws" contract that no
  /// artifact reachable through [seal] can reach. Production is always
  /// [processDataItem]; nothing but a test may pass anything else, because
  /// anything else is a way to skip the signature check.
  final DriveStateDataItemParser _parseDataItem;

  /// The most payload this format will seal, and the most [open] will inflate.
  ///
  /// 100 MiB — the same number the uploader's `maxSizeSupportedByGCMEncryption`
  /// happens to hold, and deliberately no longer *that* constant.
  ///
  /// ## Why the bound is no longer the cipher's
  ///
  /// D5 originally justified this as an AES-GCM constraint: GCM should not
  /// authenticate more than about this much in one piece, so a payload above
  /// it had to be refused rather than split or handed to unauthenticated CTR.
  /// Two things falsify that reading.
  ///
  /// First, it was already measured wrong. What GCM encrypts is the
  /// *compressed, signed* item, not the payload this number weighs: at 41,767
  /// files that is 9.55 MiB against a 52.16 MiB payload, 5.46x less than the
  /// figure being checked (§2.3). The cipher was never near its limit.
  ///
  /// Second, there is now a path with no cipher in it at all. A public drive's
  /// artifact is signed and not encrypted, so a bound inherited from GCM would
  /// have nothing to inherit from and would have to be dropped — which is
  /// plainly wrong, because the cost the bound guards is real and is the same
  /// on both paths.
  ///
  /// ## What it does guard
  ///
  /// The **producer's memory**, which §2.3 measures: building a payload this
  /// size takes a process from a 263 MiB baseline to a peak near 950 MiB — the
  /// exported object graph, then `jsonEncode`, then UTF-8, then sealing — and
  /// that peak is reached before any cipher is involved. On the web that is a
  /// browser tab with a hard ceiling, and dart2js strings are UTF-16, so the
  /// same payload is nearer twice the size there. Encryption adds one buffer
  /// of the *compressed* size to it, which is noise.
  ///
  /// So the bound is the same number for both privacy modes, on purpose. Two
  /// numbers would mean the read-side inflation limit differed by drive, which
  /// is a window in which a payload can be written by one path and refused by
  /// another. One number is checkable; two drift.
  ///
  /// The private path stays comfortably inside GCM's own limit as a
  /// consequence rather than by construction, and
  /// `drive_state_envelope_test.dart` asserts that this constant never grows
  /// past `maxSizeSupportedByGCMEncryption` so the consequence keeps holding.
  static const int defaultMaxPlaintextBytes = 100 * 1024 * 1024;

  /// The most plaintext [open] will produce before refusing.
  ///
  /// [defaultMaxPlaintextBytes] both ways in production: [seal] will not
  /// produce a payload at or above it, so no artifact this codec wrote can
  /// legitimately open to one. Sharing the constant is what keeps the two
  /// halves from drifting into a window where a payload can be written and not
  /// read, or read and not written.
  ///
  /// Only this half is injectable, and only for tests — [seal] always weighs
  /// against [defaultMaxPlaintextBytes] — so a test can build a payload that
  /// is over the *reader's* limit without allocating 100 MiB to do it.
  final int maxPlaintextBytes;

  DriveStateEnvelopeCodec({
    ArDriveCrypto? crypto,
    // Injectable only so a test can prove the bound holds without allocating
    // 100 MiB to watch it hold.
    int? maxPlaintextBytes,
    @visibleForTesting DriveStateDataItemParser? parseDataItem,
  })  : _crypto = crypto ?? ArDriveCrypto(),
        _parseDataItem = parseDataItem ?? processDataItem,
        maxPlaintextBytes = maxPlaintextBytes ?? defaultMaxPlaintextBytes;

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
  /// and — for a private drive only — encrypts that item under the drive key
  /// [protection] carries.
  ///
  /// Refuses, rather than throws, when the payload is too large or the wallet
  /// will not sign.
  ///
  /// There is no way to ask for the unencrypted form. [protection] is resolved
  /// from the drive's own `privacy` column by
  /// [DriveStateProtection.forDrive], and only its `public` arm produces a
  /// [DriveStateUnencrypted]; the switch below is exhaustive over a sealed
  /// type, so a third form of protection is a compile error rather than a
  /// silent fall-through to the clear.
  Future<DriveStateSealResult> seal({
    required Uint8List plaintext,
    required DriveStateProtection protection,
    required Wallet wallet,
  }) async {
    // D5, weighed against this format's own bound rather than the cipher's:
    // what it guards is the producer's memory, which is spent identically
    // whether or not the result is later encrypted. See
    // [defaultMaxPlaintextBytes].
    if (plaintext.lengthInBytes >= defaultMaxPlaintextBytes) {
      return DriveStateSealResult.refused(
        DriveStateEnvelopeFailure.plaintextTooLarge,
        '${plaintext.lengthInBytes} bytes is at or above the '
        '$defaultMaxPlaintextBytes byte payload boundary; '
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

    switch (protection) {
      case DriveStateEncrypted(driveKey: final driveKey):
        final secretBox = await _crypto.encrypt(signedItem, driveKey);

        return DriveStateSealResult.sealed(
          DriveStateEnvelope.encrypted(
            // Ciphertext then MAC; the nonce goes in the Cipher-IV tag.
            body: secretBox.concatenation(nonce: false),
            cipherIv: Uint8List.fromList(secretBox.nonce),
          ),
        );

      case DriveStateUnencrypted():
        // The signed data item *is* the transaction body. No cipher, so no
        // `Cipher` and no `Cipher-IV` tag — and their absence is what tells a
        // reader which of the two chains produced this.
        return DriveStateSealResult.sealed(
          DriveStateEnvelope.inTheClear(body: signedItem),
        );
    }
  }

  /// Opens [envelope] under [protection] and returns its payload only if the
  /// data item inside verifies and was signed by [expectedOwnerAddress].
  ///
  /// [protection] comes from the drive row in the caller's own database, which
  /// is trustworthy; the envelope's cipher tags come from an indexer, which is
  /// not. The first thing this does is check one against the other, in both
  /// directions.
  ///
  /// Never throws: every way this can go wrong is a
  /// [DriveStateEnvelopeFailure] the caller logs before falling back. That is a
  /// contract and not a hope, so it is held in two places — every step below
  /// that can fail is caught where it fails and named, and [_openOrThrow] is
  /// wrapped once more here so that a step which grows a new failure mode later
  /// still cannot turn a bad artifact into a failed sync (§2.5). A caught
  /// throwable is a bug worth fixing, but it is never worth a drive.
  Future<DriveStateOpenResult> open({
    required DriveStateEnvelope envelope,
    required DriveStateProtection protection,
    required String expectedOwnerAddress,
  }) async {
    try {
      return await _openOrThrow(
        envelope: envelope,
        protection: protection,
        expectedOwnerAddress: expectedOwnerAddress,
      );
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        'Reading the artifact threw where it should have refused, which is a '
        'bug; the drive falls back to an ordinary sync: $e',
      );
    }
  }

  Future<DriveStateOpenResult> _openOrThrow({
    required DriveStateEnvelope envelope,
    required DriveStateProtection protection,
    required String expectedOwnerAddress,
  }) async {
    // The cipher/privacy cross-check, before anything else is looked at.
    //
    // The same shape as the `Block-Start`/`Block-End` check in
    // `drive_state_import.dart`: a claim made by an untrusted source, checked
    // against something trustworthy. Here the untrusted claim is whether the
    // artifact carries a cipher, and the trustworthy fact is the privacy of
    // the drive in this client's own database.
    //
    // Both directions are refusals, and neither is cosmetic. A plaintext
    // artifact accepted for a private drive would be this reader agreeing to
    // a format no correct producer can emit — the exposure it represents is
    // already permanent by the time it is read, but treating it as ordinary
    // is how a broken producer stays unnoticed. A ciphertext artifact for a
    // public drive has no key that could ever open it, and saying so is more
    // useful than the `decryptionFailed` that would otherwise be reported for
    // a key this reader never had.
    if (protection.isEncrypted && !envelope.isEncrypted) {
      return const DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.plaintextForPrivateDrive,
        'The drive is private and this artifact declares no cipher; a private '
        'drive is never published in the clear',
      );
    }

    if (!protection.isEncrypted && envelope.isEncrypted) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.ciphertextForPublicDrive,
        'The drive is public and this artifact declares ${envelope.cipher}; '
        'a public drive has no key to open it with',
      );
    }

    if (envelope.isEncrypted && envelope.cipher != Cipher.aes256gcm) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.unsupportedCipher,
        'Encrypted drive state artifacts are AES256-GCM only, and this one '
        'declares ${envelope.cipher}',
      );
    }

    if (expectedOwnerAddress.isEmpty) {
      return const DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.ownerMismatch,
        'No expected owner address to verify against',
      );
    }

    final unwrapped = await _unwrap(envelope, protection);
    if (unwrapped.failure != null) {
      return DriveStateOpenResult.failed(
        unwrapped.failure!,
        unwrapped.reason!,
      );
    }
    final binary = unwrapped.bytes!;

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
    final int signatureType;
    try {
      signatureType = _readSignatureType(binary);
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        'The decrypted bytes do not begin with a readable ANS-104 signature '
        'type: $e',
      );
    }

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
      item = await _parseDataItem(
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
    } catch (e) {
      // Not `on Error`. Draining someone else's stream is the one step here
      // whose failure modes belong to another package: a range that does not
      // fit the item raises an `Error`, but a stream is equally free to carry
      // an `Exception`, and an `on Error` clause lets that one straight past
      // the caller's fallback and into a failed sync.
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.malformedFrame,
        'The data item\'s data could not be read back: $e',
      );
    }

    final Uint8List plaintext;
    try {
      plaintext = _inflateBounded(compressed);
    } on _PlaintextLimitExceeded catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.decompressedTooLarge,
        'The signed data expands past the $maxPlaintextBytes byte limit '
        '(${compressed.lengthInBytes} compressed bytes reached ${e.reached})',
      );
    } catch (e) {
      return DriveStateOpenResult.failed(
        DriveStateEnvelopeFailure.decompressionFailed,
        'The signed data is not a gzip stream: $e',
      );
    }

    return DriveStateOpenResult.opened(plaintext, signerAddress);
  }

  /// The signed data item inside [envelope]: decrypted for a private drive,
  /// and the body itself for a public one.
  ///
  /// An exhaustive switch over the sealed [DriveStateProtection] rather than
  /// an `if (encrypted) … else …`, deliberately. An `else` would make "do not
  /// decrypt" the fall-through for anything the type grows later, and "do not
  /// decrypt" is the branch that must never be reached by accident.
  Future<
      ({
        Uint8List? bytes,
        DriveStateEnvelopeFailure? failure,
        String? reason,
      })> _unwrap(
    DriveStateEnvelope envelope,
    DriveStateProtection protection,
  ) async {
    switch (protection) {
      case DriveStateEncrypted(driveKey: final driveKey):
        try {
          return (
            bytes: await _crypto.decrypt(
              envelope.body,
              driveKey,
              // Non-null because the cross-check above established that an
              // encrypted protection met an encrypted envelope, and an
              // encrypted envelope cannot exist without its IV.
              envelope.cipherIv!,
            ),
            failure: null,
            reason: null,
          );
        } catch (e) {
          return (
            bytes: null,
            failure: DriveStateEnvelopeFailure.decryptionFailed,
            reason: 'The body did not decrypt under the drive key: $e',
          );
        }

      case DriveStateUnencrypted():
        // No authenticated envelope around these bytes at all, which is why
        // the data item signature below is not merely one check among several
        // here — it is the only one standing between an anonymous upload and
        // this drive's rows.
        return (bytes: envelope.body, failure: null, reason: null);
    }
  }

  /// Gunzips [compressed], refusing at [maxPlaintextBytes] rather than
  /// wherever the process runs out of memory.
  ///
  /// The bound is enforced *during* inflation, not after it, which is the only
  /// place it can be: the size a gzip stream records in its trailer is chosen
  /// by whoever wrote the stream, so a bomb is free to understate it, and by
  /// the time the decoder could check the trailer it has already allocated the
  /// output. Writing through a capped stream costs one comparison per write.
  Uint8List _inflateBounded(Uint8List compressed) {
    final output = _BoundedOutputStream(maxPlaintextBytes);
    GZipDecoder().decodeStream(InputStream(compressed), output);
    return _asBytes(output.getBytes());
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

/// Raised by [_BoundedOutputStream] and turned into a
/// [DriveStateEnvelopeFailure.decompressedTooLarge] by the only caller.
/// Private so that "never throws" stays true of everything this library
/// exposes.
class _PlaintextLimitExceeded implements Exception {
  /// How much had been written when the limit was passed. Not the payload's
  /// real size — nothing here ever learns that — but enough to say in a log
  /// that the limit was reached rather than approached.
  final int reached;

  const _PlaintextLimitExceeded(this.reached);

  @override
  String toString() => '_PlaintextLimitExceeded($reached)';
}

/// An `archive` output stream that refuses to grow past a limit.
///
/// Subclassing rather than reimplementing: `Inflate` reads back through
/// `subset` to resolve LZ77 back references, so this has to be a real
/// [OutputStream] and not merely something with the same write methods.
///
/// ## Two gates, because one of them is only as complete as the package
///
/// The obvious way to bound an output stream is to override its write methods.
/// That works, and it is the gate that matters, because it refuses *before* the
/// buffer is grown — which is the whole point when the input is a bomb whose
/// expansion is the attack. But it is only sound while the set of methods
/// overridden here is the set the decoder actually calls, and that set is the
/// package's business, not ours. `archive`'s `OutputStream` writes bytes
/// through six methods; three are overridden below and the other three
/// (`writeUint16`, `writeUint32`, `writeUint64`) reach the buffer *through*
/// [writeByte] in the pinned version — an implementation detail nobody promised
/// and nothing here can pin. A version that stopped delegating, or that grew a
/// seventh method, would leave the guard passing its tests and guarding
/// nothing.
///
/// So the second gate is [length]. Overriding the base class's field with a
/// getter and a setter puts a check on the one thing every write path must do:
/// no byte can be counted as written without it, whatever method admitted it.
/// It refuses later than the first gate — the buffer may already have been
/// grown for the write in progress, bounded by that write's own size — but it
/// cannot be routed around by a method this class has not heard of.
///
/// [admittedBytes] is what keeps the first gate honest: every byte the write
/// overrides let through is counted, so a test can compare the total against
/// [length] after a real decode and fail the moment those two disagree. See
/// `drive_state_envelope_test.dart`, which is the alarm for exactly the
/// `archive` upgrade described above.
class _BoundedOutputStream extends OutputStream {
  final int limit;

  /// Shadows `OutputStream.length`, which the base class declares as a plain
  /// field and reads and writes virtually on every path that puts a byte in
  /// the buffer.
  int _length = 0;

  int _admitted = 0;

  _BoundedOutputStream(this.limit);

  /// How many bytes reached the buffer through a write method this class
  /// guards. Equal to [length] exactly when the guards are complete.
  int get admittedBytes => _admitted;

  @override
  int get length => _length;

  @override
  set length(int value) {
    if (value > limit) {
      throw _PlaintextLimitExceeded(value);
    }
    _length = value;
  }

  void _admit(int adding) {
    if (_length + adding > limit) {
      throw _PlaintextLimitExceeded(_length + adding);
    }
    _admitted += adding;
  }

  @override
  void writeByte(int value) {
    _admit(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    _admit(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    _admit(stream.length);
    super.writeInputStream(stream);
  }

  // `Inflate` calls neither of these on the path `decodeStream` takes, but both
  // reset `length`, so leaving them alone would leave [admittedBytes] counting
  // bytes that are no longer there and quietly disarm the alarm above.
  @override
  void clear() {
    super.clear();
    _admitted = 0;
  }

  @override
  void reset() {
    super.reset();
    _admitted = 0;
  }
}
