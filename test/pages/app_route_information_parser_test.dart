import 'package:ardrive/pages/pages.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fileId = '00000000-0000-0000-0000-000000000001';
  const driveId = '00000000-0000-0000-0000-000000000002';
  const folderId = '00000000-0000-0000-0000-000000000003';

  // A well formed base64 file key: 43 characters, all of them valid base64url.
  // Must be canonical base64: for a 32-byte key the final character carries
  // only 4 significant bits, so its low 2 bits must be zero or Dart's strict
  // decoder throws 'Invalid encoding before padding'. 'Q' (index 16) is valid;
  // 'q' (index 42) is not.
  const validFileKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  // Same shape, for the drive links.
  const validDriveKey = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  late AppRouteInformationParser parser;

  Future<AppRoutePath> parse(String location) =>
      parser.parseRouteInformation(RouteInformation(uri: Uri.parse(location)));

  setUp(() {
    parser = AppRouteInformationParser();
  });

  group('shared file routes', () {
    test('parses a link carrying a valid file key', () async {
      final routePath = await parse(
        '/file/$fileId/view?$fileKeyQueryParamName=$validFileKey',
      );

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileKey, isNotNull);
      expect(routePath.sharedRawFileKey, validFileKey);
      expect(routePath.sharedFileKeyIsDamaged, isFalse);
    });

    test('parses a link carrying no file key', () async {
      final routePath = await parse('/file/$fileId/view');

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileKey, isNull);
      expect(routePath.sharedRawFileKey, isNull);
      // Nothing was damaged - the link simply never carried a key.
      expect(routePath.sharedFileKeyIsDamaged, isFalse);
    });

    test('does not throw on a truncated file key', () async {
      // Mail clients and chat apps truncate long links routinely. 41 characters
      // is not a valid base64 length, so decoding it throws.
      final truncatedFileKey = validFileKey.substring(0, 41);

      final routePath = await parse(
        '/file/$fileId/view?$fileKeyQueryParamName=$truncatedFileKey',
      );

      // The page still loads, without a key, so the file can be unlocked by
      // hand instead of the router blowing up.
      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileKey, isNull);
      expect(routePath.sharedRawFileKey, isNull);
      // ... and the page is told why the key is missing, so it can say the
      // link is damaged instead of asking for a key with no explanation.
      expect(routePath.sharedFileKeyIsDamaged, isTrue);
    });

    test('does not throw on a file key with invalid characters', () async {
      final routePath = await parse(
        '/file/$fileId/view?$fileKeyQueryParamName=not-a-valid-key!!',
      );

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileKey, isNull);
      expect(routePath.sharedRawFileKey, isNull);
      expect(routePath.sharedFileKeyIsDamaged, isTrue);
    });

    test('does not throw on an empty file key', () async {
      final routePath =
          await parse('/file/$fileId/view?$fileKeyQueryParamName=');

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileKey, isNull);
      // An empty parameter is an absent key, not a mangled one.
      expect(routePath.sharedFileKeyIsDamaged, isFalse);
    });
  });

  group('drive routes', () {
    test('parses a link carrying a valid drive key', () async {
      final routePath = await parse(
        '/drives/$driveId?name=My%20Drive'
        '&$driveKeyQueryParamName=$validDriveKey',
      );

      expect(routePath.driveId, driveId);
      expect(routePath.driveName, 'My Drive');
      expect(routePath.sharedDriveKey, isNotNull);
      expect(routePath.sharedRawDriveKey, validDriveKey);
    });

    test('does not throw on a truncated drive key', () async {
      // 41 characters is not a valid base64 length, so decoding it throws.
      final truncatedDriveKey = validDriveKey.substring(0, 41);

      final routePath = await parse(
        '/drives/$driveId?name=My%20Drive'
        '&$driveKeyQueryParamName=$truncatedDriveKey',
      );

      // The drive route still resolves, without a key, instead of the router
      // blowing up while parsing.
      expect(routePath.driveId, driveId);
      expect(routePath.driveName, 'My Drive');
      expect(routePath.sharedDriveKey, isNull);
      expect(routePath.sharedRawDriveKey, isNull);
    });

    test('does not throw on a drive key with invalid characters', () async {
      final routePath = await parse(
        '/drives/$driveId?$driveKeyQueryParamName=not-a-valid-key!!',
      );

      expect(routePath.driveId, driveId);
      expect(routePath.sharedDriveKey, isNull);
      expect(routePath.sharedRawDriveKey, isNull);
    });

    test('does not throw on an empty drive key', () async {
      final routePath =
          await parse('/drives/$driveId?$driveKeyQueryParamName=');

      expect(routePath.driveId, driveId);
      expect(routePath.sharedDriveKey, isNull);
      expect(routePath.sharedRawDriveKey, isNull);
    });

    test('falls back to the folder route when the drive key is damaged',
        () async {
      final truncatedDriveKey = validDriveKey.substring(0, 41);

      final routePath = await parse(
        '/drives/$driveId/folders/$folderId'
        '?$driveKeyQueryParamName=$truncatedDriveKey',
      );

      expect(routePath.driveId, driveId);
      expect(routePath.driveFolderId, folderId);
      expect(routePath.sharedDriveKey, isNull);
    });

    test('parses a folder link', () async {
      final routePath = await parse('/drives/$driveId/folders/$folderId');

      expect(routePath.driveId, driveId);
      expect(routePath.driveFolderId, folderId);
    });
  });
}
