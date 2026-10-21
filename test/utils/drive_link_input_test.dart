import 'package:ardrive/utils/drive_link_input.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the "Open a drive" field accepts: a Drive ID, or any link the address
/// bar would understand, with the folder and key that link carried.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const folderId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';
  const fileId = 'd5eaed3d-6e5d-7f4e-bd5f-9f4d3e6f7a81';

  // 32 zero bytes, base64url: a well-formed key the parser can decode.
  const rawKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

  Future<DriveLinkInputDrive> drive(String raw) async {
    final input = await DriveLinkInput.parse(raw);
    expect(input, isA<DriveLinkInputDrive>(), reason: raw);
    return input as DriveLinkInputDrive;
  }

  group('a bare id', () {
    test('is a drive', () async {
      final input = await drive(driveId);

      expect(input.driveId, driveId);
      expect(input.folderId, isNull);
      expect(input.driveKey, isNull);
    });

    test('survives the whitespace a paste brings along', () async {
      final input = await drive('  $driveId\n');

      expect(input.driveId, driveId);
    });

    test('may be the 43 character base64url form', () async {
      const base64Id = 'MjBVmHGxUSUzOzvXPJ6_mg7qxfrmBvBnm6ZJbZkMrRA';

      final input = await drive(base64Id);

      expect(input.driveId, base64Id);
    });
  });

  group('a drive link', () {
    test('copied from the app carries its route in the fragment', () async {
      final input = await drive('https://app.ardrive.io/#/drives/$driveId');

      expect(input.driveId, driveId);
    });

    test('brings its folder along', () async {
      final input = await drive(
        'https://app.ardrive.io/#/drives/$driveId/folders/$folderId',
      );

      expect(input.driveId, driveId);
      expect(input.folderId, folderId);
    });

    test('brings its key along, decoded and raw', () async {
      final input = await drive(
        'https://app.ardrive.io/#/drives/$driveId?driveKey=$rawKey',
      );

      expect(input.driveId, driveId);
      expect(input.driveKey, isNotNull);
      expect(input.rawDriveKey, rawKey);
    });

    test('works as a bare path', () async {
      final input = await drive('/drives/$driveId');

      expect(input.driveId, driveId);
    });

    test('works without a scheme', () async {
      final input = await drive('app.ardrive.io/#/drives/$driveId');

      expect(input.driveId, driveId);
    });

    test('works from a path-routed host', () async {
      final input = await drive('https://example.com/drives/$driveId');

      expect(input.driveId, driveId);
    });
  });

  group('other links', () {
    test('a shared file link is recognised as a file', () async {
      final input = await DriveLinkInput.parse(
        'https://app.ardrive.io/#/file/$fileId/view',
      );

      expect(input, isA<DriveLinkInputOtherLink>());
      expect((input as DriveLinkInputOtherLink).isFile, isTrue);
      expect(input.route.sharedFileId, fileId);
    });

    test('a raw transaction link is recognised, and is not a file', () async {
      const txId = 'MjBVmHGxUSUzOzvXPJ6_mg7qxfrmBvBnm6ZJbZkMrRA';

      final input = await DriveLinkInput.parse(
        'https://app.ardrive.io/#/view/$txId',
      );

      expect(input, isA<DriveLinkInputOtherLink>());
      expect((input as DriveLinkInputOtherLink).isFile, isFalse);
      expect(input.route.rawTransactionId, txId);
    });
  });

  group('anything else', () {
    for (final raw in [
      '',
      '   ',
      'hello',
      'not-a-uuid-at-all',
      'https://app.ardrive.io/',
      'https://app.ardrive.io/#/drives',
      'https://app.ardrive.io/#/sign-in',
      'https://example.com/some/other/page',
    ]) {
      test('"$raw" is unrecognised', () async {
        final input = await DriveLinkInput.parse(raw);

        expect(input, isA<DriveLinkInputUnrecognised>());
      });
    }
  });
}
