import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:test/test.dart';

/// Everything here works on wallets and keys generated in the test. There is
/// no fixture key material, and there must never be.
void main() {
  final codec = DriveStateEnvelopeCodec();
  final crypto = ArDriveCrypto();
  final aesGcm = AesGcm.with256bits();

  late Wallet owner;
  late String ownerAddress;
  late SecretKey driveKey;
  late Uint8List plaintext;

  /// The inverse of the seal, up to but not including the frame: what a
  /// tampering test needs in order to put different bytes inside a body that
  /// still decrypts.
  Future<Uint8List> unsealFrame(DriveStateEnvelope envelope) async {
    final compressed =
        await crypto.decrypt(envelope.body, driveKey, envelope.cipherIv);
    return Uint8List.fromList(GZipDecoder().decodeBytes(compressed));
  }

  /// Seals arbitrary bytes the way [DriveStateEnvelopeCodec.seal] would, so a
  /// test can hand the codec a body that is validly encrypted but wrong
  /// inside.
  Future<DriveStateEnvelope> sealBytes(List<int> frame,
      {bool compress = true}) async {
    final body = compress ? GZipEncoder().encode(frame)! : frame;
    final secretBox = await crypto.encrypt(Uint8List.fromList(body), driveKey);

    return DriveStateEnvelope(
      body: secretBox.concatenation(nonce: false),
      cipherIv: Uint8List.fromList(secretBox.nonce),
    );
  }

  setUpAll(() async {
    owner = await Wallet.generate();
    ownerAddress = await owner.getAddress();
    driveKey = await aesGcm.newSecretKey();
    // Compressible, like the JSON container this carries in production, and
    // long enough that gzip and the frame both have something to do.
    plaintext = Uint8List.fromList(utf8.encode(
      jsonEncode({
        'version': 1,
        'sections': {
          'rows': List.generate(
            256,
            (i) => {'id': 'entity-$i', 'name': 'file-$i', 'size': i * 1024},
          ),
        },
      }),
    ));
  });

  group('DriveStateEnvelopeCodec', () {
    group('seal', () {
      test(
          'produces a body that is neither the plaintext nor readable '
          'without the drive key', () async {
        final result = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: owner,
        );

        expect(result.isSealed, isTrue, reason: result.toString());
        final envelope = result.envelope!;

        expect(envelope.cipher, Cipher.aes256gcm);
        expect(envelope.cipherIv.length, 12);
        expect(envelope.body, isNot(equals(plaintext)));
        expect(
          envelope.body.length,
          greaterThan(0),
        );
        // The plaintext must not survive anywhere in the body.
        expect(
          String.fromCharCodes(envelope.body).contains('entity-0'),
          isFalse,
        );
      });

      test('refuses a payload sitting exactly on the AES-GCM boundary',
          () async {
        final result = await codec.seal(
          plaintext: Uint8List(maxSizeSupportedByGCMEncryption),
          driveKey: driveKey,
          wallet: owner,
        );

        expect(result.isRefused, isTrue);
        expect(result.envelope, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.plaintextTooLarge);
      });

      test(
          'refuses a payload above the AES-GCM boundary rather than '
          'reaching for CTR', () async {
        final result = await codec.seal(
          plaintext: Uint8List(maxSizeSupportedByGCMEncryption + 1),
          driveKey: driveKey,
          wallet: owner,
        );

        expect(result.isRefused, isTrue);
        expect(result.envelope, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.plaintextTooLarge);
        expect(result.reason, contains('AES-GCM boundary'));
      });

      test('reports a wallet whose public key cannot be read', () async {
        final result = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: _GarbledWallet(),
        );

        expect(result.isRefused, isTrue);
        expect(result.envelope, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.signingFailed);
      });

      test('reports a wallet that will not sign', () async {
        final result = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: _RefusingWallet(),
        );

        expect(result.isRefused, isTrue);
        expect(result.failure, DriveStateEnvelopeFailure.signingFailed);
      });
    });

    group('open', () {
      late DriveStateEnvelope sealed;

      setUpAll(() async {
        final result = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: owner,
        );
        sealed = result.envelope!;
      });

      test('round trips the plaintext byte for byte', () async {
        final result = await codec.open(
          envelope: sealed,
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isTrue, reason: result.toString());
        expect(result.plaintext, equals(plaintext));
        expect(result.ownerAddress, ownerAddress);
      });

      test('rejects a body whose ciphertext was tampered with', () async {
        final tampered = Uint8List.fromList(sealed.body);
        tampered[tampered.length ~/ 2] ^= 0xFF;

        final result = await codec.open(
          envelope: DriveStateEnvelope(
            body: tampered,
            cipherIv: sealed.cipherIv,
          ),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects a body whose MAC was tampered with', () async {
        final tampered = Uint8List.fromList(sealed.body);
        tampered[tampered.length - 1] ^= 0xFF;

        final result = await codec.open(
          envelope: DriveStateEnvelope(
            body: tampered,
            cipherIv: sealed.cipherIv,
          ),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects a truncated body', () async {
        final result = await codec.open(
          envelope: DriveStateEnvelope(
            body: Uint8List.sublistView(sealed.body, 0, 32),
            cipherIv: sealed.cipherIv,
          ),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects a body sealed under a different drive key', () async {
        final result = await codec.open(
          envelope: sealed,
          driveKey: await aesGcm.newSecretKey(),
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects tags that declare anything other than AES256-GCM',
          () async {
        final result = await codec.open(
          envelope: DriveStateEnvelope(
            body: sealed.body,
            cipherIv: sealed.cipherIv,
            cipher: Cipher.aes256ctr,
          ),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.unsupportedCipher);
        expect(result.reason, contains('AES256-CTR'));
      });

      test('rejects an artifact signed by another wallet', () async {
        final stranger = await Wallet.generate();

        final theirs = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: stranger,
        );

        // It opens for its own owner...
        final forThem = await codec.open(
          envelope: theirs.envelope!,
          driveKey: driveKey,
          expectedOwnerAddress: await stranger.getAddress(),
        );
        expect(forThem.isOpened, isTrue, reason: forThem.toString());

        // ...and not for this drive's owner, even though the drive key and
        // the signature are both perfectly valid.
        final forUs = await codec.open(
          envelope: theirs.envelope!,
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(forUs.isOpened, isFalse);
        expect(forUs.plaintext, isNull);
        expect(forUs.failure, DriveStateEnvelopeFailure.ownerMismatch);
      });

      test('rejects a payload the owner did not sign', () async {
        // Rewrite the last byte of the frame. The payload is always last, so
        // this changes what was signed without touching the owner key or the
        // signature, then re-seals it so the body still decrypts.
        final frame = await unsealFrame(sealed);
        frame[frame.length - 1] ^= 0xFF;

        final result = await codec.open(
          envelope: await sealBytes(frame),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.signatureInvalid);
      });

      test('rejects a body that is not a gzip stream', () async {
        final result = await codec.open(
          envelope: await sealBytes(
            utf8.encode('this was never compressed'),
            compress: false,
          ),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decompressionFailed);
      });

      test('rejects bytes that decompress to something that is not a frame',
          () async {
        final result = await codec.open(
          envelope: await sealBytes(utf8.encode('not a drive state frame')),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.malformedFrame);
      });

      test('rejects a frame that does not carry the format\'s magic bytes',
          () async {
        final frame = await unsealFrame(sealed);
        frame[0] ^= 0xFF;

        final result = await codec.open(
          envelope: await sealBytes(frame),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.malformedFrame);
      });

      test('rejects a frame whose declared lengths do not add up', () async {
        final frame = await unsealFrame(sealed);

        final result = await codec.open(
          envelope: await sealBytes(frame.sublist(0, frame.length - 1)),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.malformedFrame);
      });

      test('rejects a frame written by a later version of the format',
          () async {
        final frame = await unsealFrame(sealed);
        frame[9] = DriveStateEnvelopeCodec.frameVersion + 1;

        final result = await codec.open(
          envelope: await sealBytes(frame),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(
          result.failure,
          DriveStateEnvelopeFailure.unsupportedFrameVersion,
        );
      });

      test('rejects a frame signed with a scheme it cannot verify', () async {
        final frame = await unsealFrame(sealed);
        // Signature type 4 is Solana in ANS-104's numbering, which this
        // client has no verifier for.
        frame[11] = 4;

        final result = await codec.open(
          envelope: await sealBytes(frame),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(
          result.failure,
          DriveStateEnvelopeFailure.unsupportedSignatureType,
        );
      });

      test('refuses to open anything when it has no owner to check against',
          () async {
        final result = await codec.open(
          envelope: sealed,
          driveKey: driveKey,
          expectedOwnerAddress: '',
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.ownerMismatch);
      });
    });
  });
}

/// A wallet whose owner key is not something that can be decoded, standing in
/// for an extension that answered with nonsense.
class _GarbledWallet extends Wallet {
  @override
  Future<String> getOwner() async => 'not base64 !!';

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async =>
      Uint8List(512);
}

/// A wallet that cannot sign, standing in for a browser extension that
/// declines or has dropped its permission.
class _RefusingWallet extends Wallet {
  @override
  Future<String> getOwner() async => 'irrelevant';

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async =>
      throw StateError('the user declined');
}
