import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/domain/drive_password_info.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

/// Known-answer vectors for the drive key.
///
/// Every value here was computed by `deriveDriveKey` in ardrive-core-js 5.1.1
/// (the CLI's and desktop's code) for the public test wallet in
/// `test/test_utils/utils.dart`. They pin today's v1 and v2 derivations, so a
/// refactor that changes a key - which would lock every user out of their
/// drives - fails here first.
const _driveId = '6939b9e0-cc98-42cb-bae0-5888eca78885';

const _coreJs = {
  ('correct horse', DriveSignatureType.v1):
      'dc83e5411fd1324e2b4efd3d71f6eddb5245498ed35e34fa8b865dff09a82502',
  ('correct horse', DriveSignatureType.v2):
      'c4f7943a1409e6381b5a03d1ca1308d42df14c474300de360bedd03b93b0cde9',
  ('pässwörd ä', DriveSignatureType.v1):
      'ee0070a03a00229ca1bc7ff4bfe2f09a32b992d14ea144adf7baf52dc04b966b',
  ('pässwörd ä', DriveSignatureType.v2):
      '2dc379a51718be0b72a23ceb279cded1df2fed5dd5509dd9f27cd409f2588dfc',
  ('密码 test', DriveSignatureType.v1):
      'e06a7f1b94d11951343c6c99be8da5df7d71378125bb5f0ef34904a2325684e8',
  ('密码 test', DriveSignatureType.v2):
      'e9013ab9d135ad53a49fc496b83ca4fbf7110a0e7953e78994662ae695d18d72',
};

String _hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Future<String> _hex(DriveKey key) async => _hexOf(await key.key.extractBytes());

void main() {
  final crypto = ArDriveCrypto();
  final wallet = getTestWallet();

  group('drive key known answers', () {
    for (final type in DriveSignatureType.values) {
      test('an ASCII password gives core-js\'s $type key', () async {
        final key = await crypto.deriveDriveKey(
            wallet, _driveId, 'correct horse', type, null);

        expect(await _hex(key), _coreJs[('correct horse', type)]);
        expect(key.generated, isTrue);
      });

      for (final password in ['pässwörd ä', '密码 test']) {
        test(
            'a non-ASCII password: the plain $type key is web\'s own, the '
            'double-encoded one is core-js\'s', () async {
          final plain = await crypto.deriveDriveKey(
              wallet, _driveId, password, type, null);

          // Web has always encoded once. This is what every web-made drive
          // with this password was made with, and it must never change.
          expect(await _hex(plain), isNot(_coreJs[(password, type)]));

          final signature =
              await crypto.walletSignatureForDrive(wallet, _driveId, type);
          final infos = drivePasswordInfos(password);

          expect(infos, hasLength(2));
          expect(
            await _hex(await crypto.driveKeyFromSignature(signature, infos[0],
                generated: true)),
            await _hex(plain),
          );
          expect(
            await _hex(await crypto.driveKeyFromSignature(signature, infos[1],
                generated: true)),
            _coreJs[(password, type)],
          );
        });
      }
    }

    test('deriveDriveKey is the step functions put together', () async {
      for (final type in DriveSignatureType.values) {
        final whole = await crypto.deriveDriveKey(
            wallet, _driveId, 'correct horse', type, null);
        final signature =
            await crypto.walletSignatureForDrive(wallet, _driveId, type);
        final parts = await crypto.driveKeyFromSignature(
            signature, utf8.encode('correct horse'),
            generated: true);

        expect(await _hex(parts), await _hex(whole));
      }
    });

    test(
        'a v1 drive with a stored signature derives the same key as signing, '
        'and is marked not generated', () async {
      const password = 'correct horse';
      final v1Signature = await crypto.walletSignatureForDrive(
          wallet, _driveId, DriveSignatureType.v1);
      final v2Key = await crypto.deriveDriveKey(
          wallet, _driveId, password, DriveSignatureType.v2, null);
      final box = await crypto.encrypt(v1Signature, v2Key.key);

      final record = DriveSignatureEntity(
        driveId: _driveId,
        signatureFormat: '1',
        cipher: 'AES256-GCM',
        cipherIv: utils.encodeBytesToBase64(box.nonce),
        data: Uint8List.fromList(box.concatenation(nonce: false)),
      );

      final key = await crypto.deriveDriveKey(
          wallet, _driveId, password, DriveSignatureType.v1, record);

      expect(await _hex(key), _coreJs[(password, DriveSignatureType.v1)]);
      expect(key.generated, isFalse);

      // The wrong password fails AES-GCM authentication on the record itself.
      await expectLater(
        crypto.deriveDriveKey(
            wallet, _driveId, 'wrong', DriveSignatureType.v1, record),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('drivePasswordInfos', () {
    test('ASCII has one candidate, its UTF-8 bytes', () {
      expect(
          drivePasswordInfos('correct horse'), [utf8.encode('correct horse')]);
    });

    test('"ä" double-encodes to c383c2a4, as core-js does', () {
      expect(_hexOf(coreJsPasswordInfo('ä')), 'c383c2a4');
      expect(drivePasswordInfos('ä').map(_hexOf), ['c3a4', 'c383c2a4']);
    });

    test('an empty password is one empty candidate', () {
      expect(drivePasswordInfos(''), [<int>[]]);
    });
  });
}
