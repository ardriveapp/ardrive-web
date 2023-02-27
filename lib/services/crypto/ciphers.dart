import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/services/crypto/stream_aes.dart';
import 'package:ardrive/services/crypto/stream_cipher.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;

StreamingCipher cipherBufferImpl(String? cipherName) {
  final impls = {
    Cipher.aes256gcm: AesGcm.with256bits(),
    Cipher.aes256ctr: AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty),
  };
  final impl = impls[cipherName];
  if (impl == null) throw ArgumentError();
  return impl;
}

FutureOr<DecryptStream> cipherStreamDecryptImpl(
  String? cipherName, {
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
  String? cipherName, {
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
