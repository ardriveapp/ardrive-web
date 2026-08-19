import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
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

  /// Offsets into an Arweave signed ANS-104 data item. The tests know the
  /// layout on purpose: reaching a particular field is how you prove the codec
  /// notices when that field is wrong.
  const signatureStart = 2;
  const signatureLength = 512;
  const ownerLength = 512;
  const tagsStart =
      signatureStart + signatureLength + ownerLength + 1 /* target */ + 1;

  /// The inverse of the seal, up to but not including the data item: what a
  /// tampering test needs in order to put different bytes inside a body that
  /// still decrypts.
  Future<Uint8List> unsealItem(DriveStateEnvelope envelope) async =>
      crypto.decrypt(envelope.body, driveKey, envelope.cipherIv);

  /// Encrypts arbitrary bytes the way [DriveStateEnvelopeCodec.seal] would, so
  /// a test can hand the codec a body that is validly encrypted but wrong
  /// inside.
  Future<DriveStateEnvelope> sealBytes(List<int> body) async {
    final secretBox = await crypto.encrypt(Uint8List.fromList(body), driveKey);

    return DriveStateEnvelope(
      body: secretBox.concatenation(nonce: false),
      cipherIv: Uint8List.fromList(secretBox.nonce),
    );
  }

  /// A genuinely signed data item over [data], for the cases where the item
  /// has to be valid and it is its *contents* that are wrong.
  Future<Uint8List> signedItemOver(List<int> data, Wallet wallet) async {
    final item = DataItem.withBlobData(data: Uint8List.fromList(data))
      ..setOwner(await wallet.getOwner());
    await item.sign(ArweaveSigner(wallet));

    return (await item.asBinary()).takeBytes();
  }

  setUpAll(() async {
    owner = await Wallet.generate();
    ownerAddress = await owner.getAddress();
    driveKey = await aesGcm.newSecretKey();
    // Compressible, like the JSON container this carries in production, and
    // long enough that gzip and the data item both have something to do.
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

      test('seals an ANS-104 data item the owner signed, not a bespoke frame',
          () async {
        final result = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: owner,
        );

        final binary = await unsealItem(result.envelope!);

        // Signature type 1, Arweave, little endian in the first two bytes.
        expect(binary[0], 1);
        expect(binary[1], 0);

        // The owner travels in the item itself, which is the entire point:
        // a reader that only has these bytes can still name the signer.
        final itemOwner = utils.encodeBytesToBase64(
          binary.sublist(
            signatureStart + signatureLength,
            signatureStart + signatureLength + ownerLength,
          ),
        );
        expect(await utils.ownerToAddress(itemOwner), ownerAddress);

        // No tags, no target, no anchor: the flags are both 'absent' and the
        // tag count is zero.
        expect(binary[signatureStart + signatureLength + ownerLength], 0);
        expect(binary[signatureStart + signatureLength + ownerLength + 1], 0);
        expect(
          utils.byteArrayToLong(binary.sublist(tagsStart, tagsStart + 8)),
          0,
        );

        // And the item's data is the gzipped payload, so the signature covers
        // compressed bytes rather than expanded ones.
        expect(binary.length, lessThan(plaintext.length));
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
        // Rewrite the last byte of the data item. The data is always last, so
        // this changes what was signed without touching the owner key or the
        // signature, then re-seals it so the body still decrypts.
        final binary = await unsealItem(sealed);
        binary[binary.length - 1] ^= 0xFF;

        final result = await codec.open(
          envelope: await sealBytes(binary),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.signatureInvalid);
      });

      test('rejects a data item whose signature was replaced', () async {
        // The other half of the same question: leave the signed bytes alone
        // and break the signature instead. Nothing else about the item is
        // wrong, so only the verification can catch this.
        final binary = await unsealItem(sealed);
        binary[signatureStart] ^= 0xFF;

        final result = await codec.open(
          envelope: await sealBytes(binary),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.signatureInvalid);
      });

      test('rejects signed data that is not a gzip stream', () async {
        // A real data item, really signed by the owner, whose data is simply
        // not compressed. Authorship is fine; the contents are not.
        final result = await codec.open(
          envelope: await sealBytes(
            await signedItemOver(utf8.encode('never compressed'), owner),
          ),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.decompressionFailed);
      });

      /// A real bomb, not a mock of one: a run of zeros gzips at about
      /// 1000:1, which is the whole difficulty. Nothing about the compressed
      /// size says what it will expand to, and the size recorded in the gzip
      /// trailer is chosen by whoever wrote the stream.
      Future<DriveStateEnvelope> sealBomb(int expandedBytes) async {
        final compressed = GZipEncoder().encode(Uint8List(expandedBytes))!;
        expect(
          compressed.length * 100,
          lessThan(expandedBytes),
          reason: 'a payload that does not expand by two orders of magnitude '
              'is not testing what this test is about',
        );

        return sealBytes(await signedItemOver(compressed, owner));
      }

      test('refuses a signed payload that expands past the limit', () async {
        // The bound is injected small so this costs a megabyte rather than a
        // hundred. What it proves is the same: verification cannot save the
        // decompressor, because the bytes really are signed - the owner's own
        // artifact, re-published by anyone who can copy it, is enough.
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);

        final result = await bounded.open(
          envelope: await sealBomb(4 * 1024 * 1024),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(
          result.failure,
          DriveStateEnvelopeFailure.decompressedTooLarge,
          reason: result.reason,
        );
        // A typed refusal, not an exception, and distinct from "this is not a
        // gzip stream" - it is a perfectly good one.
        expect(
          result.failure,
          isNot(DriveStateEnvelopeFailure.decompressionFailed),
        );
      });

      test('opens a payload that sits exactly on the limit', () async {
        // The other side of the boundary, so the test above cannot be passed
        // by a codec that refuses everything.
        final payload = Uint8List(64 * 1024);
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);

        final result = await bounded.open(
          envelope: (await bounded.seal(
            plaintext: payload,
            driveKey: driveKey,
            wallet: owner,
          ))
              .envelope!,
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.isOpened, isTrue, reason: result.reason);
        expect(result.plaintext, hasLength(64 * 1024));
      });

      test('refuses a payload one byte over the limit', () async {
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);

        final result = await bounded.open(
          envelope: (await bounded.seal(
            plaintext: Uint8List(64 * 1024 + 1),
            driveKey: driveKey,
            wallet: owner,
          ))
              .envelope!,
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decompressedTooLarge);
      });

      test('bounds decompression at the boundary seal refuses to cross',
          () async {
        // The default, which is what production runs with: the two halves
        // share one constant so no payload can be writable and unreadable, or
        // readable and unwritable.
        expect(
          DriveStateEnvelopeCodec().maxPlaintextBytes,
          maxSizeSupportedByGCMEncryption,
        );
      });

      test('rejects bytes too short to be a data item at all', () async {
        final result = await codec.open(
          envelope: await sealBytes(utf8.encode('not a data item')),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        expect(result.failure, DriveStateEnvelopeFailure.malformedFrame);
      });

      test('rejects a data item whose tag lengths run off the end', () async {
        final binary = await unsealItem(sealed);
        // The eight bytes at tagsStart + 8 are the size of the tag section.
        // Claim far more of them than the item contains.
        for (var i = 0; i < 6; i++) {
          binary[tagsStart + 8 + i] = 0xFF;
        }

        final result = await codec.open(
          envelope: await sealBytes(binary),
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );

        // Structurally hopeless bytes and unsigned bytes are the same
        // rejection: the owner did not sign this, whatever it is.
        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.signatureInvalid);
      });

      test('rejects a data item signed with a scheme it cannot verify',
          () async {
        final binary = await unsealItem(sealed);
        // Signature type 4 is Solana in ANS-104's numbering, which this
        // client has no verifier for. The field is little endian.
        binary[0] = 4;

        final result = await codec.open(
          envelope: await sealBytes(binary),
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

    test('a sealed artifact survives a full round trip through gzip and GCM',
        () async {
      // Deliberately incompressible, so the gzip layer is exercised on data
      // it cannot shrink as well as on the JSON above.
      final awkward = Uint8List.fromList(
        List.generate(4096, (i) => (i * 31 + 7) % 251),
      );

      final result = await codec.seal(
        plaintext: awkward,
        driveKey: driveKey,
        wallet: owner,
      );

      final opened = await codec.open(
        envelope: result.envelope!,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(opened.isOpened, isTrue, reason: opened.toString());
      expect(opened.plaintext, equals(awkward));
    });

    test('opens an empty payload', () async {
      final result = await codec.seal(
        plaintext: Uint8List(0),
        driveKey: driveKey,
        wallet: owner,
      );

      final opened = await codec.open(
        envelope: result.envelope!,
        driveKey: driveKey,
        expectedOwnerAddress: ownerAddress,
      );

      expect(opened.isOpened, isTrue, reason: opened.toString());
      expect(opened.plaintext, isEmpty);
    });

    /// `open` documents that it never throws, and the whole fallback design
    /// rests on it: a caller logs a typed failure and syncs the ordinary way,
    /// so a throw here is not a bad artifact, it is a failed drive (§2.5).
    ///
    /// Reading the item's data back is the one step whose failure modes belong
    /// to another package, and it was caught `on Error` — which lets an
    /// `Exception` straight past. No artifact reachable through `seal` can
    /// produce one, so the parse is swapped for a stand-in that does; that is
    /// the only thing the seam is for.
    group('the never-throws contract', () {
      Future<DriveStateOpenResult> openWithFailingStream(Object error) async {
        final sealed = await codec.seal(
          plaintext: plaintext,
          driveKey: driveKey,
          wallet: owner,
        );

        final codecWithBrokenItem = DriveStateEnvelopeCodec(
          parseDataItem: ({
            required dataItemStreamGenerator,
            required id,
            required length,
            required signatureConfig,
          }) async =>
              ProcessedDataItem(
            id: id,
            signature: '',
            owner: utils.encodeBytesToBase64(await owner.getOwner().then(
                  (o) => utils.decodeBase64ToBytes(o),
                )),
            target: '',
            anchor: '',
            tags: const [],
            dataLength: 0,
            dataStreamGenerator: () =>
                Stream<Uint8List>.error(error, StackTrace.current),
          ),
        );

        return codecWithBrokenItem.open(
          envelope: sealed.envelope!,
          driveKey: driveKey,
          expectedOwnerAddress: ownerAddress,
        );
      }

      test('an Exception from the item data stream is a typed failure',
          () async {
        final result = await openWithFailingStream(
          Exception('the gateway hung up mid-item'),
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.malformedFrame);
        expect(result.reason, contains('could not be read back'));
      });

      test('an Error from the item data stream is a typed failure', () async {
        final result = await openWithFailingStream(
          RangeError('the item does not contain that range'),
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.malformedFrame);
      });
    });
  });

  /// The decompression bound overrides `OutputStream`'s write methods, and is
  /// only as complete as the set of methods `GZipDecoder` actually calls. That
  /// set is `archive`'s to change, and changing it would leave the bound's own
  /// tests passing while the bound guarded nothing — so it is asserted here,
  /// directly against the pinned package.
  ///
  /// If this fails after an `archive` upgrade, do not relax it. Read
  /// `_BoundedOutputStream` and extend the guard to whatever the decoder now
  /// writes through.
  group('the archive decoder writes only through methods the bound guards', () {
    /// Counts bytes exactly as `_BoundedOutputStream` admits them: through
    /// `writeByte`, `writeBytes` and `writeInputStream`, the three methods it
    /// overrides. `writeUint16`/`32`/`64` reach the buffer through `writeByte`
    /// in this version, so they are covered without being overridden — if that
    /// stops being true, [admitted] falls behind [length] and this fails.
    void expectFullyAdmitted(List<int> payload) {
      final recorder = _AdmissionRecorder();

      GZipDecoder().decodeStream(
        InputStream(GZipEncoder().encode(payload)!),
        recorder,
      );

      expect(recorder.getBytes(), equals(payload));
      expect(
        recorder.admitted,
        recorder.length,
        reason: 'the decoder put ${recorder.length - recorder.admitted} bytes '
            'in the buffer without going through writeByte, writeBytes or '
            'writeInputStream; _BoundedOutputStream no longer bounds those '
            'bytes before they are allocated',
      );
    }

    test('for a compressible payload', () {
      expectFullyAdmitted(List<int>.filled(256 * 1024, 0));
    });

    test('for an incompressible payload, which deflate stores verbatim', () {
      // Random-looking bytes deflate to stored blocks, which is the path that
      // reaches `writeInputStream` rather than the Huffman decoder.
      expectFullyAdmitted(
        List<int>.generate(256 * 1024, (i) => (i * 2654435761) & 0xff),
      );
    });

    test('for a payload with long back references', () {
      // LZ77 matches are copied with `writeBytes(subset(-distance))`, and a
      // repeated block is what produces them.
      final block = List<int>.generate(4096, (i) => (i * 31 + 7) % 251);
      expectFullyAdmitted([for (var i = 0; i < 64; i++) ...block]);
    });

    test('every write method the base class declares is accounted for', () {
      // A structural canary rather than a behavioural one: this class names
      // every member of `OutputStreamBase`, so an `archive` that grows a new
      // write method stops this file compiling instead of silently opening a
      // seventh way into the buffer.
      final surface = _WriteSurface();

      surface
        ..writeByte(1)
        ..writeBytes([1, 2])
        ..writeUint16(1)
        ..writeUint32(1)
        ..writeUint64(1)
        ..writeInputStream(InputStream([1, 2, 3]));

      expect(
        surface.called,
        {
          'writeByte',
          'writeBytes',
          'writeUint16',
          'writeUint32',
          'writeUint64',
          'writeInputStream',
        },
        reason: 'these are the six ways bytes enter an archive OutputStream; '
            '_BoundedOutputStream guards three directly and the other three '
            'through writeByte',
      );
    });
  });
}

/// An `OutputStream` that counts the bytes admitted through the three write
/// methods `_BoundedOutputStream` guards, so a test can compare that total
/// against the buffer's actual length.
class _AdmissionRecorder extends OutputStream {
  int admitted = 0;

  @override
  void writeByte(int value) {
    admitted += 1;
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    admitted += len ?? bytes.length;
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    admitted += stream.length;
    super.writeInputStream(stream);
  }
}

/// Implements `OutputStreamBase` rather than extending `OutputStream`, so that
/// a write method added to the interface is a compile error here.
class _WriteSurface extends OutputStreamBase {
  final called = <String>{};

  @override
  int get length => 0;

  @override
  void flush() => called.add('flush');

  @override
  void writeByte(int value) => called.add('writeByte');

  @override
  void writeBytes(List<int> bytes, [int? len]) => called.add('writeBytes');

  @override
  void writeInputStream(InputStreamBase stream) =>
      called.add('writeInputStream');

  @override
  void writeUint16(int value) => called.add('writeUint16');

  @override
  void writeUint32(int value) => called.add('writeUint32');

  @override
  void writeUint64(int value) => called.add('writeUint64');
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
