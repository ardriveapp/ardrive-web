import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive_crypto/src/constants.dart';
import 'package:ardrive_crypto/src/stream_aes.dart';
import 'package:ardrive_crypto/src/stream_cipher.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
// `Cipher` is hidden above because this package has its own: the constant
// names that go on a transaction's tags. The algorithm type still has to be
// nameable, so it comes back under a prefix.
import 'package:cryptography/cryptography.dart' as crypto show Cipher;

/// The buffered cipher for [cipherName], for data small enough to decrypt
/// whole.
///
/// AES-CTR sat commented out here for years, with the note that this
/// implementation "generates a 16 byte nonce by default". That is true of
/// *generating* one - `newNonce()` returns sixteen bytes where ArDrive's
/// `Cipher-IV` is twelve - but it says nothing about decrypting, which is all
/// this function is used for. `AesCtr` zero pads a short nonce into the
/// counter block, so the twelve byte IV on a transaction is already the block
/// its data was encrypted under. Verified: encrypting under a 12 byte nonce
/// and under that nonce followed by four zero bytes gives identical ciphertext.
///
/// What leaving it out actually did was throw [ArgumentError] for CTR, one
/// line before the `switch` in `decryptTransactionData` that handles it
/// carefully. Callers that swallow errors turned that into "this file cannot
/// be previewed", so **every private AES-CTR file failed to preview** - while
/// downloading the same file worked, because downloads go through
/// [cipherStreamDecryptImpl], which always implemented CTR.
crypto.Cipher cipherBufferImpl(String cipherName) {
  final impls = <String, crypto.Cipher>{
    Cipher.aes256gcm: AesGcm.with256bits(),
    Cipher.aes256ctr: AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty),
  };
  final impl = impls[cipherName];
  if (impl == null) throw ArgumentError();
  return impl;
}

FutureOr<DecryptStream> cipherStreamDecryptImpl(
  String cipherName, {
  required Uint8List keyData,
  bool gcmTooLargeToBuffer = false,
}) async {
  final Map<String, FutureOr<DecryptStream> Function(Uint8List)> ctrs = {
    // NOTE: streaming AES-GCM does *not* verify the MAC — it trims the tag and
    // decrypts with AES-CTR underneath. Anything decrypted through it must be
    // authenticated another way. Prefer buffering + decryptTransactionData().
    //
    // [gcmTooLargeToBuffer] is the single exception, and it is the caller's
    // assertion that buffering is impossible — see
    // [AesGcmStream.unauthenticatedTooLargeToBuffer]. Every other GCM caller
    // goes through [AesGcmStream.unauthenticated], which stays subject to the
    // kill switch.
    Cipher.aes256gcm: gcmTooLargeToBuffer
        ? AesGcmStream.unauthenticatedTooLargeToBuffer
        : AesGcmStream.unauthenticated,
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
