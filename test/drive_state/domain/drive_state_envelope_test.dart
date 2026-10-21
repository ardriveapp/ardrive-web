import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/drive_state/domain/drive_state_envelope.dart';
import 'package:ardrive/drive_state/domain/drive_state_protection.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:ardrive_uploader/ardrive_uploader.dart'
    show maxSizeSupportedByGCMEncryption;
import 'package:cryptography/cryptography.dart' show AesGcm, SecretKey;
import 'package:test/test.dart';

/// Everything here works on keys generated in the test. There is no fixture
/// key material, and there must never be.
void main() {
  final codec = DriveStateEnvelopeCodec();
  final crypto = ArDriveCrypto();
  final aesGcm = AesGcm.with256bits();

  late SecretKey driveKey;
  late Uint8List plaintext;

  /// The two protections, built the only way they can be built: from a drive's
  /// `privacy` column and whatever key came with it. Nothing in this file
  /// fabricates one, because nothing anywhere can.
  late DriveStateProtection privateDrive;
  late DriveStateProtection publicDrive;

  DriveStateProtection protectionFor(SecretKey key) =>
      DriveStateProtection.forDrive(
        privacy: DrivePrivacyTag.private,
        driveKey: key,
      ).protection!;

  /// Encrypts arbitrary bytes the way [DriveStateEnvelopeCodec.seal] would, so
  /// a test can hand the codec a body that is validly encrypted but wrong
  /// inside.
  Future<DriveStateEnvelope> sealBytes(List<int> body) async {
    final secretBox = await crypto.encrypt(Uint8List.fromList(body), driveKey);

    return DriveStateEnvelope.encrypted(
      body: secretBox.concatenation(nonce: false),
      cipherIv: Uint8List.fromList(secretBox.nonce),
    );
  }

  /// A SQLite file's 16 byte header followed by [body]: the shape of an
  /// uncompressed artifact, which this codec never inspects past the header.
  List<int> sqliteFile(List<int> body) =>
      [...ascii.encode('SQLite format 3'), 0, ...body];

  setUpAll(() async {
    driveKey = await aesGcm.newSecretKey();
    privateDrive = protectionFor(driveKey);
    publicDrive = DriveStateProtection.forDrive(
      privacy: DrivePrivacyTag.public,
      driveKey: null,
    ).protection!;
    // Compressible, like the payload this carries in production.
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
        final result =
            await codec.seal(plaintext: plaintext, protection: privateDrive);

        expect(result.isSealed, isTrue, reason: result.toString());
        final envelope = result.envelope!;

        expect(envelope.cipher, Cipher.aes256gcm);
        expect(envelope.cipherIv!.length, 12);
        expect(envelope.body, isNot(equals(plaintext)));
        // The plaintext must not survive anywhere in the body.
        expect(
          String.fromCharCodes(envelope.body).contains('entity-0'),
          isFalse,
        );
      });

      test('encrypts the gzipped payload and nothing else', () async {
        // No wrapper and no signature: what GCM holds is the gzip stream
        // itself (D16), so the body is the payload's compressed size plus the
        // 16 byte tag.
        final result =
            await codec.seal(plaintext: plaintext, protection: privateDrive);
        final envelope = result.envelope!;

        final inner = await crypto.decrypt(
          envelope.body,
          driveKey,
          envelope.cipherIv!,
        );
        expect(inner.sublist(0, 2), [0x1f, 0x8b]);
        expect(GZipDecoder().decodeBytes(inner), equals(plaintext));
        expect(envelope.body.length, inner.length + 16);
      });

      test('refuses a payload sitting exactly on the payload boundary',
          () async {
        final result = await codec.seal(
          plaintext: Uint8List(
            DriveStateEnvelopeCodec.defaultMaxPlaintextBytes,
          ),
          protection: privateDrive,
        );

        expect(result.isRefused, isTrue);
        expect(result.envelope, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.plaintextTooLarge);
      });

      test(
          'refuses a payload above the boundary rather than '
          'reaching for CTR', () async {
        final result = await codec.seal(
          plaintext: Uint8List(
            DriveStateEnvelopeCodec.defaultMaxPlaintextBytes + 1,
          ),
          protection: privateDrive,
        );

        expect(result.isRefused, isTrue);
        expect(result.envelope, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.plaintextTooLarge);
        expect(result.reason, contains('payload boundary'));
      });

      test(
          'refuses the same payload for a public drive, where there is no '
          'cipher for the bound to have come from', () async {
        // D5's bound is on the producer's memory, not on AES-GCM, so it holds
        // at the same number on a path with no cipher in it.
        final result = await codec.seal(
          plaintext: Uint8List(
            DriveStateEnvelopeCodec.defaultMaxPlaintextBytes,
          ),
          protection: publicDrive,
        );

        expect(result.isRefused, isTrue);
        expect(result.envelope, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.plaintextTooLarge);
      });
    });

    group('open', () {
      late DriveStateEnvelope sealed;

      setUpAll(() async {
        final result =
            await codec.seal(plaintext: plaintext, protection: privateDrive);
        sealed = result.envelope!;
      });

      test('round trips the plaintext byte for byte', () async {
        final result =
            await codec.open(envelope: sealed, protection: privateDrive);

        expect(result.isOpened, isTrue, reason: result.toString());
        expect(result.plaintext, equals(plaintext));
      });

      test('rejects a body whose ciphertext was tampered with', () async {
        final tampered = Uint8List.fromList(sealed.body);
        tampered[tampered.length ~/ 2] ^= 0xFF;

        final result = await codec.open(
          envelope: DriveStateEnvelope.encrypted(
            body: tampered,
            cipherIv: sealed.cipherIv!,
          ),
          protection: privateDrive,
        );

        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects a body whose MAC was tampered with', () async {
        final tampered = Uint8List.fromList(sealed.body);
        tampered[tampered.length - 1] ^= 0xFF;

        final result = await codec.open(
          envelope: DriveStateEnvelope.encrypted(
            body: tampered,
            cipherIv: sealed.cipherIv!,
          ),
          protection: privateDrive,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects a truncated body', () async {
        final result = await codec.open(
          envelope: DriveStateEnvelope.encrypted(
            body: Uint8List.sublistView(sealed.body, 0, 32),
            cipherIv: sealed.cipherIv!,
          ),
          protection: privateDrive,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects a body sealed under a different drive key', () async {
        final result = await codec.open(
          envelope: sealed,
          protection: protectionFor(await aesGcm.newSecretKey()),
        );

        expect(result.failure, DriveStateEnvelopeFailure.decryptionFailed);
      });

      test('rejects tags that declare anything other than AES256-GCM',
          () async {
        final result = await codec.open(
          envelope: DriveStateEnvelope.encrypted(
            body: sealed.body,
            cipherIv: sealed.cipherIv!,
            cipher: Cipher.aes256ctr,
          ),
          protection: privateDrive,
        );

        expect(result.failure, DriveStateEnvelopeFailure.unsupportedCipher);
        expect(result.reason, contains('AES256-CTR'));
      });

      test('opens a SQLite file that was never compressed', () async {
        final file = sqliteFile(plaintext);
        final result = await codec.open(
          envelope: await sealBytes(file),
          protection: privateDrive,
        );

        expect(result.failure, isNull, reason: result.reason);
        expect(result.plaintext, file);
      });

      test('opens a gzip stream and a SQLite file of the same bytes alike',
          () async {
        final file = sqliteFile(plaintext);
        final gzipped = await codec.open(
          envelope: await sealBytes(GZipEncoder().encode(file)!),
          protection: privateDrive,
        );
        final identity = await codec.open(
          envelope: await sealBytes(file),
          protection: privateDrive,
        );

        expect(gzipped.plaintext, file, reason: gzipped.reason);
        expect(identity.plaintext, file, reason: identity.reason);
      });

      test('refuses an uncompressed SQLite file one byte over the limit',
          () async {
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);
        final file = sqliteFile(Uint8List(64 * 1024 - 15));

        final result = await bounded.open(
          envelope: await sealBytes(file),
          protection: privateDrive,
        );

        expect(
          result.failure,
          DriveStateEnvelopeFailure.decompressedTooLarge,
          reason: result.reason,
        );
      });

      test('opens an uncompressed SQLite file exactly on the limit', () async {
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);
        final file = sqliteFile(Uint8List(64 * 1024 - 16));

        final result = await bounded.open(
          envelope: await sealBytes(file),
          protection: privateDrive,
        );

        expect(result.failure, isNull, reason: result.reason);
        expect(result.plaintext, hasLength(64 * 1024));
      });

      test('rejects a gzip header that does not inflate', () async {
        final result = await codec.open(
          envelope: await sealBytes([0x1f, 0x8b, ...utf8.encode('broken')]),
          protection: privateDrive,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decompressionFailed);
      });

      test('rejects a payload that is neither gzip nor SQLite', () async {
        final result = await codec.open(
          envelope: await sealBytes(utf8.encode('never compressed')),
          protection: privateDrive,
        );

        expect(result.isOpened, isFalse);
        expect(result.failure, DriveStateEnvelopeFailure.decompressionFailed);
      });

      test('rejects an empty payload', () async {
        final result = await codec.open(
          envelope: await sealBytes(const []),
          protection: privateDrive,
        );

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

        return sealBytes(compressed);
      }

      test('refuses a payload that expands past the limit', () async {
        // The bound is injected small so this costs a megabyte rather than a
        // hundred. What it proves is the same: knowing who uploaded the bytes
        // cannot save the decompressor, because the owner's own artifact,
        // re-published by anyone who can copy it, is enough.
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);

        final result = await bounded.open(
          envelope: await sealBomb(4 * 1024 * 1024),
          protection: privateDrive,
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
            protection: privateDrive,
          ))
              .envelope!,
          protection: privateDrive,
        );

        expect(result.isOpened, isTrue, reason: result.reason);
        expect(result.plaintext, hasLength(64 * 1024));
      });

      test('refuses a payload one byte over the limit', () async {
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);

        final result = await bounded.open(
          envelope: (await bounded.seal(
            plaintext: Uint8List(64 * 1024 + 1),
            protection: privateDrive,
          ))
              .envelope!,
          protection: privateDrive,
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
          DriveStateEnvelopeCodec.defaultMaxPlaintextBytes,
        );
      });

      test('the payload bound stays inside what AES-GCM will hold', () {
        // The bound is the producer's, not the cipher's, so this is a
        // consequence rather than the reason, and a consequence worth
        // checking, because the private path still runs through AES-GCM.
        //
        // It compares the *payload* bound against the cipher's limit, which
        // is conservative: what GCM actually holds is the compressed payload.
        expect(
          DriveStateEnvelopeCodec.defaultMaxPlaintextBytes,
          lessThanOrEqualTo(maxSizeSupportedByGCMEncryption),
        );
      });
    });

    test('a sealed artifact survives a full round trip through gzip and GCM',
        () async {
      // Deliberately incompressible, so the gzip layer is exercised on data
      // it cannot shrink as well as on the JSON above.
      final awkward = Uint8List.fromList(
        List.generate(4096, (i) => (i * 31 + 7) % 251),
      );

      final result =
          await codec.seal(plaintext: awkward, protection: privateDrive);
      final opened = await codec.open(
          envelope: result.envelope!, protection: privateDrive);

      expect(opened.isOpened, isTrue, reason: opened.toString());
      expect(opened.plaintext, equals(awkward));
    });

    test('opens an empty payload it sealed itself', () async {
      final result =
          await codec.seal(plaintext: Uint8List(0), protection: privateDrive);
      final opened = await codec.open(
          envelope: result.envelope!, protection: privateDrive);

      expect(opened.isOpened, isTrue, reason: opened.toString());
      expect(opened.plaintext, isEmpty);
    });

    /// A public drive's artifact: the same chain with the encryption step
    /// absent.
    group('a public drive', () {
      test('seals without a cipher, and the body is the gzipped payload',
          () async {
        final result =
            await codec.seal(plaintext: plaintext, protection: publicDrive);

        expect(result.isSealed, isTrue, reason: result.toString());
        final envelope = result.envelope!;

        // The discriminator, in the form a reader sees it: no `Cipher`, no
        // `Cipher-IV`, and nothing to put in either tag.
        expect(envelope.cipher, isNull);
        expect(envelope.cipherIv, isNull);
        expect(envelope.cipherIvAsBase64, isNull);
        expect(envelope.isEncrypted, isFalse);

        // And the body is the gzip stream itself.
        expect(envelope.body.sublist(0, 2), [0x1f, 0x8b]);
        expect(GZipDecoder().decodeBytes(envelope.body), equals(plaintext));
      });

      test('round trips the plaintext byte for byte', () async {
        final sealed =
            await codec.seal(plaintext: plaintext, protection: publicDrive);

        final result = await codec.open(
          envelope: sealed.envelope!,
          protection: publicDrive,
        );

        expect(result.isOpened, isTrue, reason: result.toString());
        expect(result.plaintext, equals(plaintext));
      });

      test('still bounds the decompression', () async {
        // No cipher ran before this, so nothing has vouched for the bytes at
        // all: the bound is the whole of the defence here.
        final bounded = DriveStateEnvelopeCodec(maxPlaintextBytes: 64 * 1024);
        final compressed = GZipEncoder().encode(Uint8List(4 * 1024 * 1024))!;

        final result = await bounded.open(
          envelope: DriveStateEnvelope.inTheClear(
            body: Uint8List.fromList(compressed),
          ),
          protection: publicDrive,
        );

        expect(
          result.failure,
          DriveStateEnvelopeFailure.decompressedTooLarge,
        );
      });

      test('still refuses bytes that are neither gzip nor SQLite', () async {
        final result = await codec.open(
          envelope: DriveStateEnvelope.inTheClear(
            body: Uint8List.fromList(utf8.encode('not an artifact')),
          ),
          protection: publicDrive,
        );

        expect(result.failure, DriveStateEnvelopeFailure.decompressionFailed);
      });
    });

    /// The cipher/privacy cross-check, in both directions.
    ///
    /// The untrusted claim is the artifact's cipher-presence; the trustworthy
    /// fact is the privacy of the drive in this client's database. Neither
    /// direction may be met half way, and the private one is the direction
    /// that matters: accepting a plaintext artifact for a private drive is
    /// this reader agreeing to a format no correct producer can emit.
    group('cipher-presence is checked against the drive', () {
      test('a plaintext artifact is refused for a private drive', () async {
        final asPublic =
            await codec.seal(plaintext: plaintext, protection: publicDrive);

        // Genuinely readable: it opens perfectly well for the drive it was
        // made for. What is wrong is only which drive it is being offered to.
        expect(
          (await codec.open(
            envelope: asPublic.envelope!,
            protection: publicDrive,
          ))
              .isOpened,
          isTrue,
        );

        final result = await codec.open(
          envelope: asPublic.envelope!,
          protection: privateDrive,
        );

        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(
          result.failure,
          DriveStateEnvelopeFailure.plaintextForPrivateDrive,
        );
        expect(result.reason, contains('never published in the clear'));
      });

      test('an encrypted artifact is refused for a public drive', () async {
        final asPrivate =
            await codec.seal(plaintext: plaintext, protection: privateDrive);

        final result = await codec.open(
          envelope: asPrivate.envelope!,
          protection: publicDrive,
        );

        expect(result.isOpened, isFalse);
        expect(result.plaintext, isNull);
        expect(
          result.failure,
          DriveStateEnvelopeFailure.ciphertextForPublicDrive,
        );

        // Not `decryptFailed`, which would blame a key this reader never had.
        expect(
          result.failure,
          isNot(DriveStateEnvelopeFailure.decryptionFailed),
        );
      });

      test('the cross-check runs before anything else is examined', () async {
        // A body that is not gzip, not SQLite, and not long enough to be
        // either. If the encoding check ran first this would come back as
        // `decompressionFailed`; the cross-check is the reason it does not,
        // and the reason a plaintext body for a private drive is never
        // inflated at all.
        final result = await codec.open(
          envelope: DriveStateEnvelope.inTheClear(
            body: Uint8List.fromList([1, 2, 3]),
          ),
          protection: privateDrive,
        );

        expect(
          result.failure,
          DriveStateEnvelopeFailure.plaintextForPrivateDrive,
        );
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
