import 'dart:typed_data';

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter_test/flutter_test.dart';

/// AES-CTR through the *buffered* decryptor, which is what previews use.
///
/// Downloads have always used the streaming decryptor, so CTR worked there and
/// only there: `cipherBufferImpl` had CTR commented out and threw
/// `ArgumentError` one line before the `switch` that handles it. Every private
/// CTR file therefore failed to preview, and silently, because the callers
/// swallow the error.
void main() {
  test('a 12 byte Cipher-IV decrypts a whole body', () async {
    // A real transaction carries a twelve byte `Cipher-IV`, and this is the
    // whole body decrypted from it.
    final key = SecretKey(List<int>.generate(32, (i) => i));
    final nonce = Uint8List.fromList(
      List<int>.generate(12, (i) => (i * 7 + 3) % 256),
    );

    // Well past one AES block, so a wrong counter block cannot pass by luck.
    final plaintext = Uint8List.fromList(
      List<int>.generate(5000, (i) => i % 256),
    );

    final aesCtr = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    final encrypted = await aesCtr.encrypt(
      plaintext,
      secretKey: key,
      nonce: nonce,
    );

    // Why no counter block is assembled anywhere: `AesCtr` zero pads a short
    // nonce into one, so the twelve bytes a transaction carries already *are*
    // the block its data was encrypted under. The note that kept CTR out of
    // `cipherBufferImpl` was about generating a nonce, not decrypting with one.
    final underFullBlock = await aesCtr.encrypt(
      plaintext,
      secretKey: key,
      nonce: Uint8List.fromList([...nonce, 0, 0, 0, 0]),
    );

    expect(encrypted.cipherText, equals(underFullBlock.cipherText));

    final decrypted = await decryptTransactionData(
      Cipher.aes256ctr,
      utils.encodeBytesToBase64(nonce),
      Uint8List.fromList(encrypted.cipherText),
      key,
    );

    expect(decrypted, equals(plaintext));
  });

  test('the buffered cipher knows both algorithms', () {
    // The regression itself: this threw ArgumentError for CTR, so every
    // private CTR preview died before reaching any decryption at all.
    expect(() => cipherBufferImpl(Cipher.aes256gcm), returnsNormally);
    expect(() => cipherBufferImpl(Cipher.aes256ctr), returnsNormally);
    expect(() => cipherBufferImpl('AES256-NOPE'), throwsArgumentError);
  });
}
