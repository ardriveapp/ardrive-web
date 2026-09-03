@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:ardrive/drive_state_sqlite/drive_state_artifact_entity.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_schema.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_seal.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:test/test.dart';

/// Stands in for signing as an ANS-104 data item. The real signer wraps the
/// payload in a frame; what matters to these tests is that the frame is
/// reversible and that the owner is checked, so a length-prefixed envelope
/// with the owner inside is enough to exercise every path.
Uint8List fakeSign(Uint8List payload, String owner) {
  final ownerBytes = Uint8List.fromList(owner.codeUnits);
  return Uint8List.fromList([ownerBytes.length, ...ownerBytes, ...payload]);
}

Future<Uint8List> fakeVerify(Uint8List frame, String expectedOwner) async {
  if (frame.isEmpty) {
    throw ArtifactSealException(ArtifactSealFailure.malformedFrame, 'empty');
  }
  final len = frame[0];
  if (frame.length < 1 + len) {
    throw ArtifactSealException(ArtifactSealFailure.malformedFrame, 'short');
  }
  final owner = String.fromCharCodes(frame.sublist(1, 1 + len));
  if (owner != expectedOwner) {
    throw ArtifactSealException(ArtifactSealFailure.ownerMismatch, owner);
  }
  return Uint8List.fromList(frame.sublist(1 + len));
}

void main() {
  const owner = 'owner-address-under-test';
  const maxPlaintext = 100 * 1024 * 1024;

  late SecretKey driveKey;
  late Uint8List artifactBytes;

  setUp(() async {
    driveKey = await cipherBufferImpl(Cipher.aes256gcm).newSecretKey();
    // A compressible body, so the gzip step is doing something observable.
    artifactBytes = Uint8List.fromList(
      List.generate(200000, (i) => 'SQLite format 3'.codeUnitAt(i % 15)),
    );
  });

  Future<SealedArtifact> seal({SecretKey? key}) => sealArtifact(
        artifactBytes,
        signPayload: (gz) async => fakeSign(gz, owner),
        driveKey: key,
      );

  Future<Uint8List> open(SealedArtifact s, {SecretKey? key, String? who}) =>
      openArtifact(
        s.body,
        driveIsPrivate: s.isEncrypted,
        cipher: s.cipher,
        cipherIv: s.cipherIv,
        verifyAndUnwrap: fakeVerify,
        expectedOwner: who ?? owner,
        maxPlaintextBytes: maxPlaintext,
        driveKey: key,
      );

  group('private drive', () {
    test('seals and opens back to the same bytes', () async {
      final sealed = await seal(key: driveKey);

      expect(sealed.isEncrypted, isTrue);
      expect(sealed.cipher, Cipher.aes256gcm);
      expect(sealed.cipherIv, isNotNull);
      // Compressed well below the plaintext, and not the plaintext itself.
      expect(sealed.body.length, lessThan(artifactBytes.length));

      expect(await open(sealed, key: driveKey), artifactBytes);
    });

    test('the sealed body is not the plaintext', () async {
      final sealed = await seal(key: driveKey);
      expect(
        String.fromCharCodes(sealed.body.take(15)),
        isNot('SQLite format 3'),
      );
    });

    test('a wrong key fails as decryptionFailed, not as something worse',
        () async {
      final sealed = await seal(key: driveKey);
      final wrong = await cipherBufferImpl(Cipher.aes256gcm).newSecretKey();
      await expectLater(
        open(sealed, key: wrong),
        throwsA(isA<ArtifactSealException>().having((e) => e.reason, 'reason',
            ArtifactSealFailure.decryptionFailed)),
      );
    });

    test('a flipped byte is caught by GCM, not imported as state', () async {
      final sealed = await seal(key: driveKey);
      final corrupted = Uint8List.fromList(sealed.body);
      corrupted[corrupted.length ~/ 2] ^= 0xFF;
      await expectLater(
        openArtifact(
          corrupted,
          driveIsPrivate: true,
          cipher: sealed.cipher,
          cipherIv: sealed.cipherIv,
          verifyAndUnwrap: fakeVerify,
          expectedOwner: owner,
          maxPlaintextBytes: maxPlaintext,
          driveKey: driveKey,
        ),
        throwsA(isA<ArtifactSealException>().having((e) => e.reason, 'reason',
            ArtifactSealFailure.decryptionFailed)),
      );
    });

    test('a signature from anyone but the owner is refused', () async {
      final sealed = await seal(key: driveKey);
      await expectLater(
        open(sealed, key: driveKey, who: 'someone-else'),
        throwsA(isA<ArtifactSealException>().having(
            (e) => e.reason, 'reason', ArtifactSealFailure.ownerMismatch)),
      );
    });
  });

  group('public drive', () {
    test('seals without a cipher and opens back', () async {
      final sealed = await seal();
      expect(sealed.isEncrypted, isFalse);
      expect(sealed.cipher, isNull);
      expect(sealed.cipherIv, isNull);
      expect(await open(sealed), artifactBytes);
    });
  });

  group('the reader refuses before it decrypts', () {
    test('a private drive whose artifact declares no cipher', () async {
      final sealed = await seal();
      await expectLater(
        openArtifact(
          sealed.body,
          driveIsPrivate: true,
          cipher: null,
          cipherIv: null,
          verifyAndUnwrap: fakeVerify,
          expectedOwner: owner,
          maxPlaintextBytes: maxPlaintext,
          driveKey: driveKey,
        ),
        throwsA(isA<ArtifactSealException>().having(
            (e) => e.reason, 'reason', ArtifactSealFailure.privacyMismatch)),
      );
    });

    test('a public drive whose artifact declares one', () async {
      final sealed = await seal(key: driveKey);
      await expectLater(
        openArtifact(
          sealed.body,
          driveIsPrivate: false,
          cipher: sealed.cipher,
          cipherIv: sealed.cipherIv,
          verifyAndUnwrap: fakeVerify,
          expectedOwner: owner,
          maxPlaintextBytes: maxPlaintext,
          driveKey: driveKey,
        ),
        throwsA(isA<ArtifactSealException>().having(
            (e) => e.reason, 'reason', ArtifactSealFailure.privacyMismatch)),
      );
    });

    test('a cipher that is not GCM', () async {
      await expectLater(
        openArtifact(
          Uint8List(64),
          driveIsPrivate: true,
          cipher: Cipher.aes256ctr,
          cipherIv: 'AAAAAAAAAAAAAAAA',
          verifyAndUnwrap: fakeVerify,
          expectedOwner: owner,
          maxPlaintextBytes: maxPlaintext,
          driveKey: driveKey,
        ),
        throwsA(isA<ArtifactSealException>().having(
            (e) => e.reason, 'reason', ArtifactSealFailure.unsupportedCipher)),
      );
    });
  });

  test('a gzip bomb is refused rather than inflated', () async {
    // 40 MiB of zeroes compresses to a few KiB. A reader that inflates first
    // and measures afterwards has already lost.
    final bomb = Uint8List(40 * 1024 * 1024);
    final sealed = await sealArtifact(
      bomb,
      signPayload: (gz) async => fakeSign(gz, owner),
    );
    expect(sealed.body.length, lessThan(100 * 1024));

    await expectLater(
      openArtifact(
        sealed.body,
        driveIsPrivate: false,
        cipher: null,
        cipherIv: null,
        verifyAndUnwrap: fakeVerify,
        expectedOwner: owner,
        maxPlaintextBytes: 1024 * 1024,
        driveKey: null,
      ),
      throwsA(isA<ArtifactSealException>().having((e) => e.reason, 'reason',
          ArtifactSealFailure.decompressedTooLarge)),
    );
  });

  group('tags', () {
    test('a private artifact carries the cipher pair, a public one neither',
        () async {
      final private = tagsFor(
        await seal(key: driveKey),
        driveId: 'drive-1',
        driveStateId: 'state-1',
        blockStart: 0,
        blockEnd: 1814228,
        entityCount: 42198,
        unixTime: DateTime.utc(2026, 8, 27),
      );
      expect(private['Cipher'], Cipher.aes256gcm);
      expect(private['Cipher-IV'], isNotNull);

      final public = tagsFor(
        await seal(),
        driveId: 'drive-1',
        driveStateId: 'state-1',
        blockStart: 0,
        blockEnd: 1814228,
        entityCount: 42198,
        unixTime: DateTime.utc(2026, 8, 27),
      );
      expect(public.containsKey('Cipher'), isFalse);
      expect(public.containsKey('Cipher-IV'), isFalse);
    });

    test('Content-Encoding is never set — it would make the artifact '
        'permanently unfetchable', () async {
      final tags = tagsFor(
        await seal(key: driveKey),
        driveId: 'drive-1',
        driveStateId: 'state-1',
        blockStart: 0,
        blockEnd: 1814228,
        entityCount: 42198,
        unixTime: DateTime.utc(2026, 8, 27),
      );
      // ar-io-node echoes this tag onto the data response. What the gateway
      // serves is ciphertext, so a browser would try to gunzip ciphertext and
      // fail with ERR_CONTENT_DECODING_FAILED. Tags are immutable.
      expect(tags.containsKey('Content-Encoding'), isFalse);
    });

    test('the experimental entity type and 0.x version are what ship here',
        () async {
      final tags = tagsFor(
        await seal(key: driveKey),
        driveId: 'drive-1',
        driveStateId: 'state-1',
        blockStart: 0,
        blockEnd: 1814228,
        entityCount: 42198,
        unixTime: DateTime.utc(2026, 8, 27),
      );
      expect(tags['Entity-Type'], 'drive-state-test');
      expect(tags['State-Version'], startsWith('0.'));
      expect(tags['State-Version'], artifactFormatVersion);
    });
  });

  group('candidate tags decide before a byte is downloaded', () {
    Map<String, String> live({String? type, String? version, int? end}) => {
          'Entity-Type': type ?? driveStateEntityType,
          'Drive-Id': 'drive-1',
          'Drive-State-Id': 'state-1',
          'State-Version': version ?? artifactFormatVersion,
          'Block-Start': '0',
          'Block-End': '${end ?? 1814228}',
          'Entity-Count': '42198',
          'Cipher': Cipher.aes256gcm,
          'Cipher-IV': 'aXY=',
        };

    DriveStateCandidate? parse(Map<String, String> tags, {int size = 1000}) =>
        DriveStateCandidate.fromTags(tags, transactionId: 'tx', dataSize: size);

    test('another entity type is not this entity at all', () {
      expect(parse(live(type: 'snapshot')), isNull);
    });

    test('a newer major is refused on tags', () {
      expect(
        parse(live(version: '1.0'))!.refuseOnTags(
          expectedDriveId: 'drive-1',
          driveIsPrivate: true,
          syncedToBlock: 0,
        ),
        DriveStateTagRefusal.unsupportedVersion,
      );
    });

    test('a range already covered is a no-op, never a rollback', () {
      expect(
        parse(live())!.refuseOnTags(
          expectedDriveId: 'drive-1',
          driveIsPrivate: true,
          syncedToBlock: 1814228,
        ),
        DriveStateTagRefusal.rangeAlreadyCovered,
      );
    });

    test('too large is decided from data.size, before downloading', () {
      expect(
        parse(live(), size: 500 * 1024 * 1024)!.refuseOnTags(
          expectedDriveId: 'drive-1',
          driveIsPrivate: true,
          syncedToBlock: 0,
          maxBytes: 100 * 1024 * 1024,
        ),
        DriveStateTagRefusal.tooLarge,
      );
    });

    test('a good candidate is accepted', () {
      expect(
        parse(live())!.refuseOnTags(
          expectedDriveId: 'drive-1',
          driveIsPrivate: true,
          syncedToBlock: 100,
        ),
        isNull,
      );
    });
  });
}
