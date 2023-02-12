import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/services/crypto/stream_cipher.dart';
import 'package:ardrive/utils/streams.dart';
import 'package:flutter/material.dart';
import 'package:webcrypto/webcrypto.dart';

const _aesBlockLengthBytes = 16;
const _aesNonceLengthBytes = 12;
const _aesCounterLengthBytes = _aesBlockLengthBytes - _aesNonceLengthBytes;
const _aesGcmTagLengthBytes = 16;

enum AesKeyLength { aes128, aes192, aes256 }

const _aes128KeyLengthBytes = 16;
const _aes192KeyLengthBytes = 24;
const _aes256KeyLengthBytes = 32;

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

  // FutureOr<AesStream> fromKeyData(Uint8List keyData);

  @override
  FutureOr<Uint8List> generateNonce() {
    final nonce = Uint8List(_aesNonceLengthBytes);
    fillRandomBytes(nonce);
    return nonce;
  }
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
    final counterInitBytes = _ctrCounterInitBytes(nonce);

    return StreamTransformer.fromBind(
      (plaintextStream) {
        return _aesCtr.encryptStream(
          plaintextStream,
          counterInitBytes,
          streamLength,
        );
      }
    );
  }

  @override
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int streamLength,
  ) {
    final counterInitBytes = _ctrCounterInitBytes(nonce);

    return StreamTransformer.fromBind(
      (ciphertextStream) {
        return _aesCtr.decryptStream(
          ciphertextStream,
          counterInitBytes,
          streamLength,
        );
      }
    );
  }

  _ctrCounterInitBytes(Uint8List nonce) {
    final ctrBytes = List.filled(_aesCounterLengthBytes, 0);
    return Uint8List.fromList(nonce.toList()..addAll(ctrBytes));
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
    int streamLength,
  ) {
    debugPrint('WARNING: Decrypting AES-GCM without MAC verification! Only do this if you know what you are doing.');

    final counterInitBytes = _gcmCounterInitBytes(nonce);
    final streamLengthNoMac = streamLength - _aesGcmTagLengthBytes;

    return StreamTransformer.fromBind(
      (ciphertextStream) {
        final ciphertextStreamNoMac = ciphertextStream
          .transform(trimData(streamLengthNoMac));
        
        return _aesCtr.decryptStream(
          ciphertextStreamNoMac,
          counterInitBytes,
          streamLengthNoMac,
        );
      }
    );
  }

  // Despite using AES-CTR interface under the hood, we can maintain 
  // compatibility with AES-GCM by implementing the same method to 
  // generate its counter initialization bytes.
  // More details: https://crypto.stackexchange.com/a/57905
  _gcmCounterInitBytes(Uint8List nonce) {
    final ctrBytes = List.filled(_aesCounterLengthBytes - 1, 0) + [2];
    return Uint8List.fromList(nonce.toList()..addAll(ctrBytes));
  }
}
