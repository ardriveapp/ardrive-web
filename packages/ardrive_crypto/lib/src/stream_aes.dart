import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_crypto/src/stream_cipher.dart';
import 'package:ardrive_crypto/src/streams.dart';
import 'package:convert/convert.dart';
import 'package:flutter/material.dart';
import 'package:webcrypto/webcrypto.dart';

const _aesBlockLengthBytes = 16;
const _aesNonceLengthBytes = 12;
const _aesCounterLengthBytes = _aesBlockLengthBytes - _aesNonceLengthBytes;

const _aes128KeyLengthBytes = 16;
const _aes192KeyLengthBytes = 24;
const _aes256KeyLengthBytes = 32;

const _webCryptoChunkSizeBytes = 256 * 1024;
const _webCryptoChuckSizeBlocks = _webCryptoChunkSizeBytes ~/ 16;

/// The counter occupies the last [_aesCounterLengthBytes] bytes of the counter
/// block, so it can only address `2^32` blocks (64 GiB) before it wraps into
/// the nonce. [AesGcmStream] burns two of those blocks (see
/// [AesGcmStream.counterBlockForOffset]).
final _maxCounterBlockValue = BigInt.from(0xFFFFFFFF);

enum AesKeyLength { aes128, aes192, aes256 }

abstract class AesStream extends CipherStream {
  static Map<AesKeyLength, int> keyLengthsBytes = {
    AesKeyLength.aes128: _aes128KeyLengthBytes,
    AesKeyLength.aes192: _aes192KeyLengthBytes,
    AesKeyLength.aes256: _aes256KeyLengthBytes,
  };

  /// The AES block size in bytes.
  ///
  /// This is the alignment a streamed decryption must start at. [counterBlock]
  /// addresses whole AES blocks, so a start offset that is not a multiple of
  /// 16 has no representable counter and would decrypt to garbage without any
  /// error being raised. It is *not* necessary to align to
  /// [streamChunkSizeBytes]: the counter of every chunk is derived from the
  /// start offset ([aesStreamTransformer]), so the chunk grid simply restarts
  /// at the resume point.
  static const int blockLengthBytes = _aesBlockLengthBytes;

  /// The size of the chunks [aesStreamTransformer] hands to the AES
  /// implementation. Every chunk but the last is exactly this size, which is
  /// why the block counter can be advanced by a constant.
  static const int streamChunkSizeBytes = _webCryptoChunkSizeBytes;

  static Future<Uint8List> generateKey(AesKeyLength keyLength) {
    final key = Uint8List(keyLengthsBytes[keyLength]!);
    fillRandomBytes(key);
    return Future.value(key);
  }

  /// Rounds [offsetBytes] down to the nearest [blockLengthBytes] boundary.
  ///
  /// Callers resuming a partial download should align the offset they already
  /// have on disk with this and re-request the (at most 15) bytes that are
  /// dropped.
  static int alignStartOffsetDown(int offsetBytes) {
    if (offsetBytes < 0) {
      throw ArgumentError.value(
        offsetBytes,
        'offsetBytes',
        'Must not be negative',
      );
    }

    return offsetBytes - (offsetBytes % blockLengthBytes);
  }

  /// Converts a byte offset into the block offset that seeds the counter.
  ///
  /// Throws an [ArgumentError] when [startOffsetBytes] is negative, is not a
  /// multiple of [blockLengthBytes], or is beyond what the
  /// [_aesCounterLengthBytes] byte counter can address. Rejecting loudly is
  /// deliberate: an unaligned offset decrypts to plausible-looking garbage.
  static BigInt startOffsetToBlockOffset(int startOffsetBytes) {
    if (startOffsetBytes < 0) {
      throw ArgumentError.value(
        startOffsetBytes,
        'startOffsetBytes',
        'Must not be negative',
      );
    }

    if (startOffsetBytes % blockLengthBytes != 0) {
      throw ArgumentError.value(
        startOffsetBytes,
        'startOffsetBytes',
        'Must be a multiple of the $blockLengthBytes byte AES block size. '
            'Align it with AesStream.alignStartOffsetDown().',
      );
    }

    final blockOffset = BigInt.from(startOffsetBytes ~/ blockLengthBytes);

    // Two blocks of headroom so that the AES-GCM counter (offset + 2) is
    // representable too.
    if (blockOffset + BigInt.two > _maxCounterBlockValue) {
      throw ArgumentError.value(
        startOffsetBytes,
        'startOffsetBytes',
        'Beyond the range addressable by the '
            '$_aesCounterLengthBytes byte AES counter',
      );
    }

    return blockOffset;
  }

  @override
  FutureOr<Uint8List> generateNonce([int lengthBytes = _aesNonceLengthBytes]) {
    final nonce = Uint8List(lengthBytes);
    fillRandomBytes(nonce);
    return nonce;
  }

  /// Transforms a stream of AES-CTR ciphertext (or plaintext, when
  /// encrypting), chunk by chunk.
  ///
  /// [startOffsetBytes] is the offset, in bytes into the *whole* ciphertext,
  /// that the input stream starts at. It defaults to `0` — the whole stream —
  /// and must be a multiple of [blockLengthBytes]; see
  /// [startOffsetToBlockOffset]. Because the keystream of AES-CTR is a pure
  /// function of the block index, seeding the counter with the start offset is
  /// all that is needed to decrypt from the middle of a file.
  @protected
  StreamTransformer<Uint8List, Uint8List> aesStreamTransformer(
    Future<Uint8List> Function(List<int>, List<int>, int) aesProcessBlock,
    Uint8List nonce, {
    int startOffsetBytes = 0,
  }) {
    if (nonce.length != _aesNonceLengthBytes) {
      throw ArgumentError.value(
        nonce,
        'nonce',
        'Nonce must be $_aesNonceLengthBytes bytes long',
      );
    }

    // Validated eagerly, before any data flows, so that a misaligned offset
    // fails at the call site instead of mid-stream.
    final startOffsetBlocks = startOffsetToBlockOffset(startOffsetBytes);

    return StreamTransformer.fromBind((inputStream) async* {
      final inputStreamChunked =
          inputStream.transform(chunkTransformer(_webCryptoChunkSizeBytes));

      var offsetBlocks = startOffsetBlocks;
      await for (final chunk in inputStreamChunked) {
        // print('offsetBlocks: $offsetBlocks');
        // print('chunk length: ${chunk.length}');
        final counterInitBytes = await counterBlock(nonce, offsetBlocks);
        // print('counterInitBytes: ${hex.encode(counterInitBytes)}');
        try {
          yield await aesProcessBlock(
            chunk,
            counterInitBytes,
            _aesCounterLengthBytes * 8,
          );
        } catch (e) {
          // print('aesProcessBlock error: $e');
          rethrow;
        }
        offsetBlocks += BigInt.from(_webCryptoChuckSizeBlocks);
        // print('next offsetBlocks: $offsetBlocks');
      }
    });
  }

  @protected
  FutureOr<Uint8List> counterBlock(Uint8List nonce, BigInt offset);
}

class AesCtrStream extends AesStream with EncryptStream, DecryptStream {
  late final AesCtrSecretKey _aesCtr;

  AesCtrStream._(this._aesCtr);

  static FutureOr<AesCtrStream> fromKeyData(Uint8List keyData) async {
    return AesCtrStream._(await AesCtrSecretKey.importRawKey(keyData));
  }

  @override
  StreamTransformer<Uint8List, Uint8List> encryptTransformer(
    Uint8List nonce,
    int streamLength,
  ) {
    return aesStreamTransformer(_aesCtr.encryptBytes, nonce);
  }

  @override
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int fileSize, {
    int startOffsetBytes = 0,
  }) {
    return aesStreamTransformer(
      _aesCtr.decryptBytes,
      nonce,
      startOffsetBytes: startOffsetBytes,
    );
  }

  /// The counter block for the AES block at [offset] blocks into the data:
  /// the 12 byte nonce followed by the 4 byte big endian block counter.
  static Uint8List counterBlockForOffset(Uint8List nonce, BigInt offset) {
    final countValue = offset;
    final countValueHex = countValue.toRadixString(16).padLeft(8, '0');
    final counter = Uint8List.fromList(hex.decode(countValueHex));
    return Uint8List.fromList(nonce.toList()..addAll(counter));
  }

  @override
  Uint8List counterBlock(Uint8List nonce, BigInt offset) =>
      counterBlockForOffset(nonce, offset);
}

// AesGcmStream uses AES-CTR under the hood, as AES-GCM does not have
// a streaming interface. As a result, the MAC cannot be generated or verified.
// Therefore, encryption is not supported, and decryption is dangerous unless
// using another data authentication method (i.e. validating the transaction)
class AesGcmStream extends AesStream with DecryptStream {
  /// Kill switch for unauthenticated AES-GCM stream decryption.
  ///
  /// It defaults to `true` only because the web download path still streams
  /// GCM today (see `lib/download/ardrive_downloader.dart`). Once that path
  /// buffers and MAC-verifies GCM instead (redesign plan §3.1), flip this to
  /// `false` and every remaining, accidental use of this class throws instead
  /// of quietly handing back unverified plaintext.
  static bool allowUnauthenticatedGcmDecryption = true;

  late final AesCtrSecretKey _aesCtr;

  AesGcmStream._(this._aesCtr);

  /// Creates a stream that decrypts AES256-GCM data **without verifying the
  /// MAC**, by running AES-CTR underneath.
  ///
  /// The name is the opt-in: anything decrypted through this must be
  /// authenticated another way (e.g. `StreamedDataItemVerifier`) or it carries
  /// no integrity guarantee at all. Prefer buffering the ciphertext and using
  /// `decryptTransactionData`, which does verify the MAC.
  static FutureOr<AesGcmStream> unauthenticated(Uint8List keyData) async {
    if (!allowUnauthenticatedGcmDecryption) {
      throw StateError(
        'Unauthenticated AES-GCM stream decryption is disabled. Buffer the '
        'ciphertext and use decryptTransactionData() so that the MAC is '
        'verified.',
      );
    }

    return AesGcmStream._(await AesCtrSecretKey.importRawKey(keyData));
  }

  /// Kept for source compatibility; [unauthenticated] says what this is.
  static FutureOr<AesGcmStream> fromKeyData(Uint8List keyData) =>
      unauthenticated(keyData);

  @override
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int fileSize, {
    int startOffsetBytes = 0,
  }) {
    debugPrint(
        'WARNING: Decrypting AES-GCM without MAC verification! Only do this if you know what you are doing.');

    // Validate before binding so a misaligned offset throws at the call site.
    AesStream.startOffsetToBlockOffset(startOffsetBytes);

    if (startOffsetBytes > fileSize) {
      throw ArgumentError.value(
        startOffsetBytes,
        'startOffsetBytes',
        'Must not be greater than the file size ($fileSize)',
      );
    }

    return StreamTransformer.fromBind((ciphertextStream) {
      // File size is used to trim the MAC from the end of the fileSize
      // stream length = file size + 16 (MAC length)
      // When starting mid-file the stream is short by everything before
      // [startOffsetBytes], so trim relative to the start offset.
      final ciphertextStreamNoMac =
          ciphertextStream.transform(trimData(fileSize - startOffsetBytes));
      return ciphertextStreamNoMac.transform(aesStreamTransformer(
        _aesCtr.decryptBytes,
        nonce,
        startOffsetBytes: startOffsetBytes,
      ));
    });
  }

  // Despite using an AES-CTR implementation under the hood, we can
  // generating the counter block the same way as AES-GCM by simply
  // adding two!
  // More details: https://crypto.stackexchange.com/a/57905
  static Uint8List counterBlockForOffset(Uint8List nonce, BigInt offset) =>
      AesCtrStream.counterBlockForOffset(nonce, offset + BigInt.two);

  @override
  Uint8List counterBlock(Uint8List nonce, BigInt offset) =>
      counterBlockForOffset(nonce, offset);
}
