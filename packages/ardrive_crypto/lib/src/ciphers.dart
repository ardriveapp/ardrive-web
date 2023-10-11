import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_crypto/src/constants.dart';
import 'package:ardrive_crypto/src/stream_aes.dart';
import 'package:ardrive_crypto/src/stream_cipher.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

StreamingCipher cipherBufferImpl(String cipherName) {
  final impls = {
    Cipher.aes256gcm: AesGcm.with256bits(),
    // Avoid this implementation because it generates a 16 byte nonce by default...
    // Cipher.aes256ctr: AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty),
  };
  final impl = impls[cipherName];
  if (impl == null) throw ArgumentError();
  return impl as StreamingCipher;
}

FutureOr<DecryptStream> cipherStreamDecryptImpl(
  String cipherName, {
  required Uint8List keyData,
}) async {
  final Map<String, FutureOr<DecryptStream> Function(Uint8List)> ctrs = {
    Cipher.aes256gcm: AesGcmStream.fromKeyData,
    Cipher.aes256ctr: AesCtrStream.fromKeyData,
  };
  final ctr = ctrs[cipherName];
  if (ctr == null) throw ArgumentError();
  final impl = await ctr(keyData);
  return impl;
}

FutureOr<EncryptStream> cipherStreamEncryptImpl(
  String cipherName, {
  required Uint8List keyData,
}) async {
  final Map<String, FutureOr<EncryptStream> Function(Uint8List)> ctrs = {
    Cipher.aes256ctr: AesCtrStream.fromKeyData,
  };
  final ctr = ctrs[cipherName];
  if (ctr == null) throw ArgumentError();
  final impl = await ctr(keyData);
  return impl;
}
