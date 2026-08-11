import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_crypto/src/streams.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests use real AES throughout.
///
/// The block cipher underneath [AesStream] is injected — [aesStreamTransformer]
/// takes the AES call as a function — so the tests below run the *production*
/// transformer, counter derivation and chunking over `package:cryptography`'s
/// pure-Dart AES-CTR instead of WebCrypto's BoringSSL binding. That is a second
/// real implementation, not a mock: the keystream has to be right or every
/// assertion fails. It also lets the suite run where the WebCrypto native
/// library is not loadable (`flutter test` without `webcrypto:setup`).
///
/// The last group closes the loop by asserting that the real WebCrypto-backed
/// [AesCtrStream] agrees with the reference, byte for byte, whenever that
/// library *is* available.
void main() {
  final keyBytes = Uint8List.fromList(
    List<int>.generate(32, (i) => (i * 7 + 11) & 0xff),
  );
  final nonce = Uint8List.fromList(
    List<int>.generate(12, (i) => (i * 31 + 3) & 0xff),
  );

  const chunkSize = AesStream.streamChunkSizeBytes;
  const blockSize = AesStream.blockLengthBytes;

  // Two full WebCrypto chunks plus a partial one, so that chunk boundaries,
  // mid-chunk offsets and the trailing partial chunk are all exercised.
  const fileSize = 2 * chunkSize + 1000;
  final plaintext = _pseudoRandomBytes(fileSize, seed: 42);

  // Offsets worth checking: the start, the first block, mid-chunk, the last
  // block before the first chunk boundary, the chunk boundaries themselves,
  // and the last block of the file.
  final offsets = <int>[
    0,
    blockSize,
    4096,
    chunkSize - blockSize,
    chunkSize,
    chunkSize + blockSize,
    2 * chunkSize,
    2 * chunkSize + blockSize,
    AesStream.alignStartOffsetDown(fileSize),
  ];

  group('AesStream offset validation', () {
    test('accepts block aligned offsets', () {
      expect(AesStream.startOffsetToBlockOffset(0), BigInt.zero);
      expect(AesStream.startOffsetToBlockOffset(16), BigInt.one);
      expect(
        AesStream.startOffsetToBlockOffset(chunkSize),
        BigInt.from(chunkSize ~/ blockSize),
      );
    });

    test('rejects misaligned offsets loudly', () {
      for (final misaligned in [1, 15, 17, 100, chunkSize - 1, 262145]) {
        expect(
          () => AesStream.startOffsetToBlockOffset(misaligned),
          throwsA(isA<ArgumentError>()),
          reason: '$misaligned is not a multiple of $blockSize',
        );
      }
    });

    test('rejects negative offsets', () {
      expect(
        () => AesStream.startOffsetToBlockOffset(-16),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => AesStream.alignStartOffsetDown(-1),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects offsets past the 32 bit counter', () {
      // The counter is 4 bytes: 2^32 blocks of 16 bytes = 64 GiB.
      const justPastTheCounter = 0xFFFFFFFF * 16;
      expect(
        () => AesStream.startOffsetToBlockOffset(justPastTheCounter),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('alignStartOffsetDown rounds down to the AES block size', () {
      expect(AesStream.alignStartOffsetDown(0), 0);
      expect(AesStream.alignStartOffsetDown(1), 0);
      expect(AesStream.alignStartOffsetDown(15), 0);
      expect(AesStream.alignStartOffsetDown(16), 16);
      expect(AesStream.alignStartOffsetDown(17), 16);
      expect(AesStream.alignStartOffsetDown(fileSize), fileSize - 8);
    });
  });

  group('counter block derivation', () {
    test('AES-CTR counter block is the nonce plus a 4 byte big endian count',
        () {
      expect(
        AesCtrStream.counterBlockForOffset(nonce, BigInt.zero),
        [...nonce, 0, 0, 0, 0],
      );
      expect(
        AesCtrStream.counterBlockForOffset(nonce, BigInt.one),
        [...nonce, 0, 0, 0, 1],
      );
      expect(
        AesCtrStream.counterBlockForOffset(nonce, BigInt.from(0x010203)),
        [...nonce, 0, 1, 2, 3],
      );
      expect(
        AesCtrStream.counterBlockForOffset(nonce, BigInt.from(0xFFFFFFFF)),
        [...nonce, 255, 255, 255, 255],
      );
    });

    test('AES-GCM counter block is the AES-CTR one, plus two', () {
      for (final blockOffset in [0, 1, 16383, 16384, 0xFFFFFF]) {
        expect(
          AesGcmStream.counterBlockForOffset(nonce, BigInt.from(blockOffset)),
          AesCtrStream.counterBlockForOffset(
            nonce,
            BigInt.from(blockOffset + 2),
          ),
          reason: 'block offset $blockOffset',
        );
      }
    });

    test('the counter block is always 16 bytes', () {
      for (final blockOffset in [0, 1, 255, 65535, 0xFFFFFFFD]) {
        expect(
          AesCtrStream.counterBlockForOffset(nonce, BigInt.from(blockOffset)),
          hasLength(16),
        );
        expect(
          AesGcmStream.counterBlockForOffset(nonce, BigInt.from(blockOffset)),
          hasLength(16),
        );
      }
    });
  });

  group('AES-CTR streamed decryption from an offset', () {
    final stream = _ReferenceAesStream(keyBytes: keyBytes, nonce: nonce);

    // Encrypting with a single AES-CTR call over the whole file, counter block
    // = nonce || 0, is what the chunked pipeline has to reproduce.
    late Uint8List ciphertext;

    setUpAll(() async {
      ciphertext = await _singleShotCtr(
        keyBytes: keyBytes,
        counterBlock: AesCtrStream.counterBlockForOffset(nonce, BigInt.zero),
        data: plaintext,
      );
    });

    test('the chunked pipeline equals a single AES-CTR call over the file',
        () async {
      final decrypted = await _collect((await stream.decryptStream(
        nonce,
        _chunked(ciphertext, 100000),
        fileSize,
      ))
          .stream);

      expect(decrypted, plaintext);
    });

    test('the encrypt transformer round trips through the decrypt transformer',
        () async {
      final encrypted = await stream.encryptStream(
        _chunked(plaintext, 100000),
        fileSize,
      );
      final encryptedBytes = await _collect(encrypted.stream);

      // The uploader's ciphertext must be exactly the single-shot CTR one, or
      // nothing else on the network can read it.
      expect(encryptedBytes, ciphertext);

      final decrypted = await _collect((await stream.decryptStream(
        encrypted.nonce,
        _chunked(encryptedBytes, 64 * 1024),
        fileSize,
      ))
          .stream);

      expect(decrypted, plaintext);
    });

    test('decrypting from an offset is byte identical to decrypt-then-slice',
        () async {
      final whole = await _collect((await stream.decryptStream(
        nonce,
        _chunked(ciphertext, chunkSize),
        fileSize,
      ))
          .stream);

      for (final offset in offsets) {
        final fromOffset = await _collect((await stream.decryptStream(
          nonce,
          _chunked(Uint8List.sublistView(ciphertext, offset), 100000),
          fileSize,
          startOffsetBytes: offset,
        ))
            .stream);

        expect(
          fromOffset,
          Uint8List.sublistView(whole, offset),
          reason: 'decrypting from byte $offset',
        );
      }
    });

    test('the offset result does not depend on how the input is chunked',
        () async {
      const offset = 3 * 16;
      final expected = Uint8List.sublistView(plaintext, offset);

      for (final inputChunkSize in [
        blockSize,
        1000,
        chunkSize,
        chunkSize + 1,
        fileSize,
      ]) {
        final fromOffset = await _collect((await stream.decryptStream(
          nonce,
          _chunked(Uint8List.sublistView(ciphertext, offset), inputChunkSize),
          fileSize,
          startOffsetBytes: offset,
        ))
            .stream);

        expect(fromOffset, expected, reason: 'input chunked at $inputChunkSize');
      }
    });

    test('decrypts the tail of the file one byte at a time', () async {
      final offset = AesStream.alignStartOffsetDown(fileSize - 1024);

      final fromOffset = await _collect((await stream.decryptStream(
        nonce,
        _chunked(Uint8List.sublistView(ciphertext, offset), 1),
        fileSize,
        startOffsetBytes: offset,
      ))
          .stream);

      expect(fromOffset, Uint8List.sublistView(plaintext, offset));
    });

    test('a misaligned start offset is rejected before any data flows',
        () async {
      for (final misaligned in [1, 15, 17, chunkSize + 1]) {
        await expectLater(
          stream.decryptStream(
            nonce,
            _chunked(ciphertext, chunkSize),
            fileSize,
            startOffsetBytes: misaligned,
          ),
          throwsA(isA<ArgumentError>()),
          reason: 'offset $misaligned',
        );
      }
    });

    test('the default start offset is unchanged behaviour', () async {
      final explicitZero = await _collect((await stream.decryptStream(
        nonce,
        _chunked(ciphertext, chunkSize),
        fileSize,
        startOffsetBytes: 0,
      ))
          .stream);
      final implicit = await _collect((await stream.decryptStream(
        nonce,
        _chunked(ciphertext, chunkSize),
        fileSize,
      ))
          .stream);

      expect(implicit, explicitZero);
      expect(implicit, plaintext);
    });
  });

  group('AES-GCM-as-CTR streamed decryption from an offset', () {
    final stream = _ReferenceAesStream(
      keyBytes: keyBytes,
      nonce: nonce,
      gcmCounter: true,
    );

    // GCM's keystream starts two blocks in, and the stored ciphertext has the
    // 16 byte MAC appended.
    late Uint8List ciphertextWithMac;

    setUpAll(() async {
      final ciphertext = await _singleShotCtr(
        keyBytes: keyBytes,
        counterBlock: AesGcmStream.counterBlockForOffset(nonce, BigInt.zero),
        data: plaintext,
      );
      ciphertextWithMac = Uint8List.fromList([
        ...ciphertext,
        ...List<int>.filled(16, 0xAB), // stand-in for the (unchecked) MAC
      ]);
    });

    test('decrypts the whole stream and drops the trailing MAC', () async {
      final decrypted = await _collect((await stream.decryptStream(
        nonce,
        _chunked(ciphertextWithMac, 100000),
        fileSize,
      ))
          .stream);

      expect(decrypted, plaintext);
      expect(decrypted, hasLength(fileSize));
    });

    test('decrypting from an offset is byte identical to decrypt-then-slice',
        () async {
      for (final offset in offsets) {
        final fromOffset = await _collect((await stream.decryptStream(
          nonce,
          _chunked(Uint8List.sublistView(ciphertextWithMac, offset), 100000),
          fileSize,
          startOffsetBytes: offset,
        ))
            .stream);

        expect(
          fromOffset,
          Uint8List.sublistView(plaintext, offset),
          reason: 'decrypting from byte $offset',
        );
      }
    });

    test('the GCM +2 counter is applied on top of the start offset, not '
        'instead of it', () async {
      const offset = 2 * 16;

      // Decrypting the offset stream with the CTR counter derivation must NOT
      // produce the plaintext: it proves the two counters really are distinct
      // and that the offset composes with, rather than replaces, the +2.
      final ctrStream = _ReferenceAesStream(keyBytes: keyBytes, nonce: nonce);
      final wrong = await _collect((await ctrStream.decryptStream(
        nonce,
        _chunked(Uint8List.sublistView(ciphertextWithMac, offset), 100000),
        fileSize,
        startOffsetBytes: offset,
      ))
          .stream);

      expect(wrong, isNot(Uint8List.sublistView(plaintext, offset)));

      final right = await _collect((await stream.decryptStream(
        nonce,
        _chunked(Uint8List.sublistView(ciphertextWithMac, offset), 100000),
        fileSize,
        startOffsetBytes: offset,
      ))
          .stream);

      expect(right, Uint8List.sublistView(plaintext, offset));
    });

    test('a misaligned start offset is rejected', () async {
      await expectLater(
        stream.decryptStream(
          nonce,
          _chunked(ciphertextWithMac, chunkSize),
          fileSize,
          startOffsetBytes: 17,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('WebCrypto-backed AesCtrStream', () {
    // Small enough to keep the native round trips quick.
    const smallSize = chunkSize + 512;
    final smallPlaintext = _pseudoRandomBytes(smallSize, seed: 7);
    final smallOffsets = <int>[
      0,
      blockSize,
      chunkSize - blockSize,
      chunkSize,
      chunkSize + blockSize,
      AesStream.alignStartOffsetDown(smallSize),
    ];

    late bool webCryptoAvailable;

    setUpAll(() async {
      webCryptoAvailable = await _webCryptoAvailable(keyBytes);
    });

    test('produces the same ciphertext as the pure-Dart reference', () async {
      if (!webCryptoAvailable) {
        markTestSkipped(_webCryptoSkipReason);
        return;
      }

      final aesCtr = await AesCtrStream.fromKeyData(keyBytes);
      final encrypted = await aesCtr.encryptStream(
        _chunked(smallPlaintext, 100000),
        smallSize,
      );
      final ciphertext = await _collect(encrypted.stream);

      final reference = await _singleShotCtr(
        keyBytes: keyBytes,
        counterBlock: AesCtrStream.counterBlockForOffset(
          encrypted.nonce,
          BigInt.zero,
        ),
        data: smallPlaintext,
      );

      expect(ciphertext, reference);
    });

    test('decrypting from an offset is byte identical to decrypt-then-slice',
        () async {
      if (!webCryptoAvailable) {
        markTestSkipped(_webCryptoSkipReason);
        return;
      }

      final aesCtr = await AesCtrStream.fromKeyData(keyBytes);
      final ciphertext = await _singleShotCtr(
        keyBytes: keyBytes,
        counterBlock: AesCtrStream.counterBlockForOffset(nonce, BigInt.zero),
        data: smallPlaintext,
      );

      for (final offset in smallOffsets) {
        final fromOffset = await _collect((await aesCtr.decryptStream(
          nonce,
          _chunked(Uint8List.sublistView(ciphertext, offset), 100000),
          smallSize,
          startOffsetBytes: offset,
        ))
            .stream);

        expect(
          fromOffset,
          Uint8List.sublistView(smallPlaintext, offset),
          reason: 'decrypting from byte $offset',
        );
      }
    });

    test('AesGcmStream decrypts from an offset and trims the MAC', () async {
      if (!webCryptoAvailable) {
        markTestSkipped(_webCryptoSkipReason);
        return;
      }

      final gcm = await AesGcmStream.unauthenticated(keyBytes);
      final ciphertext = await _singleShotCtr(
        keyBytes: keyBytes,
        counterBlock: AesGcmStream.counterBlockForOffset(nonce, BigInt.zero),
        data: smallPlaintext,
      );
      final ciphertextWithMac = Uint8List.fromList([
        ...ciphertext,
        ...List<int>.filled(16, 0xAB),
      ]);

      for (final offset in smallOffsets) {
        final fromOffset = await _collect((await gcm.decryptStream(
          nonce,
          _chunked(Uint8List.sublistView(ciphertextWithMac, offset), 100000),
          smallSize,
          startOffsetBytes: offset,
        ))
            .stream);

        expect(
          fromOffset,
          Uint8List.sublistView(smallPlaintext, offset),
          reason: 'decrypting from byte $offset',
        );
      }
    });

    test('a misaligned offset is rejected by the real streams', () async {
      if (!webCryptoAvailable) {
        markTestSkipped(_webCryptoSkipReason);
        return;
      }

      final aesCtr = await AesCtrStream.fromKeyData(keyBytes);
      await expectLater(
        aesCtr.decryptStream(
          nonce,
          _chunked(smallPlaintext, chunkSize),
          smallSize,
          startOffsetBytes: 24,
        ),
        throwsA(isA<ArgumentError>()),
      );

      final gcm = await AesGcmStream.unauthenticated(keyBytes);
      await expectLater(
        gcm.decryptStream(
          nonce,
          _chunked(smallPlaintext, chunkSize),
          smallSize,
          startOffsetBytes: 24,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('unauthenticated AES-GCM opt-in', () {
    tearDown(() {
      AesGcmStream.allowUnauthenticatedGcmDecryption = true;
    });

    test('can be switched off, at which point construction throws', () async {
      AesGcmStream.allowUnauthenticatedGcmDecryption = false;

      await expectLater(
        AesGcmStream.unauthenticated(keyBytes),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        AesGcmStream.fromKeyData(keyBytes),
        throwsA(isA<StateError>()),
      );
    });
  });
}

const _webCryptoSkipReason =
    'The WebCrypto native library is not loadable here; run '
    '`flutter pub run webcrypto:setup` to exercise the BoringSSL-backed '
    'streams. The pure-Dart reference groups cover the same logic.';

Future<bool> _webCryptoAvailable(Uint8List keyBytes) async {
  try {
    final aesCtr = await AesCtrStream.fromKeyData(keyBytes);

    // `importRawKey` alone proves nothing: it never touches BoringSSL, so the
    // library lookup is still lazy at this point and the probe would report
    // available right before the first real operation throws. Run an actual
    // encryption - generating the nonce calls `fillRandomBytes`, which is what
    // triggers the lookup - so an environment without
    // `flutter pub run webcrypto:setup` is detected here and the group skips
    // cleanly. CI runs `flutter test` per package without that setup step.
    final encrypted = await aesCtr.encryptStream(
      Stream.value(Uint8List.fromList(const [0])),
      1,
    );
    await encrypted.stream.drain<void>();

    return true;
  } catch (_) {
    return false;
  }
}

Uint8List _pseudoRandomBytes(int length, {required int seed}) {
  final random = Random(seed);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

Stream<Uint8List> _chunked(Uint8List data, int chunkSize) async* {
  for (var i = 0; i < data.length; i += chunkSize) {
    yield Uint8List.sublistView(data, i, min(i + chunkSize, data.length));
  }
}

Future<Uint8List> _collect(Stream<Uint8List> stream) async {
  final builder = BytesBuilder();
  await for (final chunk in stream) {
    builder.add(chunk);
  }
  return builder.takeBytes();
}

/// One AES-CTR call over [data], starting at [counterBlock]. Real AES, no
/// chunking, no offsets — the thing the streamed pipeline must reproduce.
Future<Uint8List> _singleShotCtr({
  required Uint8List keyBytes,
  required Uint8List counterBlock,
  required Uint8List data,
}) async {
  const cipher = DartAesCtr(macAlgorithm: MacAlgorithm.empty);
  final result = await cipher.decrypt(
    SecretBox(Uint8List.fromList(data), nonce: counterBlock, mac: Mac.empty),
    secretKey: SecretKey(keyBytes),
  );
  return Uint8List.fromList(result);
}

/// Drives the production [AesStream] pipeline with a pure-Dart AES-CTR.
class _ReferenceAesStream extends AesStream with EncryptStream, DecryptStream {
  _ReferenceAesStream({
    required Uint8List keyBytes,
    required this.nonce,
    this.gcmCounter = false,
  }) : _key = SecretKey(keyBytes);

  final SecretKey _key;
  final Uint8List nonce;

  /// Derive counters the way [AesGcmStream] does (block offset + 2) instead of
  /// the way [AesCtrStream] does.
  final bool gcmCounter;

  @override
  FutureOr<Uint8List> generateNonce([int lengthBytes = 12]) => nonce;

  @override
  Uint8List counterBlock(Uint8List nonce, BigInt offset) => gcmCounter
      ? AesGcmStream.counterBlockForOffset(nonce, offset)
      : AesCtrStream.counterBlockForOffset(nonce, offset);

  @override
  StreamTransformer<Uint8List, Uint8List> encryptTransformer(
    Uint8List nonce,
    int streamLength,
  ) {
    return aesStreamTransformer(_aesCtrProcess, nonce);
  }

  @override
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int fileSize, {
    int startOffsetBytes = 0,
  }) {
    if (!gcmCounter) {
      return aesStreamTransformer(
        _aesCtrProcess,
        nonce,
        startOffsetBytes: startOffsetBytes,
      );
    }

    // Mirrors AesGcmStream.decryptTransformer, including the MAC trim.
    AesStream.startOffsetToBlockOffset(startOffsetBytes);

    return StreamTransformer.fromBind(
      (ciphertextStream) => ciphertextStream
          .transform(trimData(fileSize - startOffsetBytes))
          .transform(aesStreamTransformer(
            _aesCtrProcess,
            nonce,
            startOffsetBytes: startOffsetBytes,
          )),
    );
  }

  /// AES-CTR is its own inverse, so this is both `encryptBytes` and
  /// `decryptBytes` — exactly like the WebCrypto pair it stands in for.
  Future<Uint8List> _aesCtrProcess(
    List<int> data,
    List<int> counterBlock,
    int counterBits,
  ) async {
    const cipher = DartAesCtr(macAlgorithm: MacAlgorithm.empty);
    final result = await cipher.decrypt(
      SecretBox(
        Uint8List.fromList(data),
        nonce: Uint8List.fromList(counterBlock),
        mac: Mac.empty,
      ),
      secretKey: _key,
    );
    return Uint8List.fromList(result);
  }
}
