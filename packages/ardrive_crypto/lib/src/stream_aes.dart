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

enum AesKeyLength { aes128, aes192, aes256 }

abstract class AesStream extends CipherStream {
  static Map<AesKeyLength, int> keyLengthsBytes = {
    AesKeyLength.aes128: _aes128KeyLengthBytes,
    AesKeyLength.aes192: _aes192KeyLengthBytes,
    AesKeyLength.aes256: _aes256KeyLengthBytes,
  };

  static Future<Uint8List> generateKey(AesKeyLength keyLength) {
    final key = Uint8List(keyLengthsBytes[keyLength]!);
    fillRandomBytes(key);
    return Future.value(key);
  }

  @override
  FutureOr<Uint8List> generateNonce([int lengthBytes = _aesNonceLengthBytes]) {
    final nonce = Uint8List(lengthBytes);
    fillRandomBytes(nonce);
    return nonce;
  }

  @protected
  StreamTransformer<Uint8List, Uint8List> aesStreamTransformer(
    Future<Uint8List> Function(List<int>, List<int>, int) aesProcessBlock,
    Uint8List nonce,
  ) {
    if (nonce.length != _aesNonceLengthBytes) {
      throw ArgumentError.value(
        nonce,
        'nonce',
        'Nonce must be $_aesNonceLengthBytes bytes long',
      );
    }

    return StreamTransformer.fromBind((inputStream) async* {
      final inputStreamChunked =
          inputStream.transform(chunkTransformer(_webCryptoChunkSizeBytes));

      var offsetBlocks = BigInt.from(0);
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
    int fileSize,
  ) {
    return aesStreamTransformer(_aesCtr.decryptBytes, nonce);
  }

  @override
  Uint8List counterBlock(Uint8List nonce, BigInt offset) {
    final countValue = offset;
    final countValueHex = countValue.toRadixString(16).padLeft(8, '0');
    final counter = Uint8List.fromList(hex.decode(countValueHex));
    return Uint8List.fromList(nonce.toList()..addAll(counter));
  }
}

// AesGcmStream uses AES-CTR under the hood, as AES-GCM does not have
// a streaming interface. As a result, the MAC cannot be generated or verified.
// Therefore, encryption is not supported, and decryption is dangerous unless
// using another data authentication method (i.e. validating the transaction)
class AesGcmStream extends AesStream with DecryptStream {
  late final AesCtrSecretKey _aesCtr;

  AesGcmStream._(this._aesCtr);

  static FutureOr<AesGcmStream> fromKeyData(Uint8List keyData) async {
    return AesGcmStream._(await AesCtrSecretKey.importRawKey(keyData));
  }

  @override
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int fileSize,
  ) {
    debugPrint(
        'WARNING: Decrypting AES-GCM without MAC verification! Only do this if you know what you are doing.');

    return StreamTransformer.fromBind((ciphertextStream) {
      // File size is used to trim the MAC from the end of the fileSize
      // stream length = file size + 16 (MAC length)
      final ciphertextStreamNoMac =
          ciphertextStream.transform(trimData(fileSize));
      return ciphertextStreamNoMac
          .transform(aesStreamTransformer(_aesCtr.decryptBytes, nonce));
    });
  }

  // Despite using an AES-CTR implementation under the hood, we can
  // generating the counter block the same way as AES-GCM by simply
  // adding two!
  // More details: https://crypto.stackexchange.com/a/57905
  @override
  Uint8List counterBlock(Uint8List nonce, BigInt offset) {
    final countValue = offset + BigInt.from(2);
    final countValueHex = countValue.toRadixString(16).padLeft(8, '0');
    final counter = Uint8List.fromList(hex.decode(countValueHex));
    return Uint8List.fromList(nonce.toList()..addAll(counter));
  }
}
