import 'dart:typed_data';

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// The kill switch and its single, named exception.
///
/// `AesGcmStream.allowUnauthenticatedGcmDecryption` is switched off for good
/// by the downloader (F24): every AES-GCM file that fits in memory is buffered
/// and MAC-verified. The exception exists for the file that cannot fit, which
/// otherwise could not be downloaded at all — see
/// [AesGcmStream.unauthenticatedTooLargeToBuffer].
///
/// `importRawKey` does not touch BoringSSL, so all of this runs anywhere
/// `flutter test` does.
void main() {
  final keyData = Uint8List.fromList(List<int>.generate(32, (i) => i));

  setUp(() => AesGcmStream.allowUnauthenticatedGcmDecryption = false);
  tearDown(() => AesGcmStream.allowUnauthenticatedGcmDecryption = true);

  test('the ordinary constructors stay disarmed', () async {
    await expectLater(
      Future.sync(() => AesGcmStream.unauthenticated(keyData)),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      Future.sync(() => AesGcmStream.fromKeyData(keyData)),
      throwsA(isA<StateError>()),
    );
  });

  test('the too-large-to-buffer constructor is the one way through', () async {
    final stream = await AesGcmStream.unauthenticatedTooLargeToBuffer(keyData);

    expect(stream, isA<AesGcmStream>());
  });

  test('the flag is what selects it, and it defaults to off', () async {
    await expectLater(
      cipherStreamDecryptImpl(Cipher.aes256gcm, keyData: keyData),
      throwsA(isA<StateError>()),
    );

    expect(
      await cipherStreamDecryptImpl(
        Cipher.aes256gcm,
        keyData: keyData,
        gcmTooLargeToBuffer: true,
      ),
      isA<AesGcmStream>(),
    );
  });

  test('it does not leak into AES-CTR, which never needed it', () async {
    expect(
      await cipherStreamDecryptImpl(
        Cipher.aes256ctr,
        keyData: keyData,
        gcmTooLargeToBuffer: true,
      ),
      isA<AesCtrStream>(),
    );
  });
}
