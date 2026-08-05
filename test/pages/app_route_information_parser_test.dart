import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
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

  // Same shape, for the drive links - and, in the v2 tests below, for a second
  // key that disagrees with [validFileKey].
  const validDriveKey = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  // 43 base64url characters: the shape of every Arweave id.
  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';

  // 12 IV bytes, base64url encoded.
  const cipherIv = '9tR2kX0pLmQz8sQ1';

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

    test('a v1 link carries no payload', () async {
      // Every link ArDrive produced before the v2 schema. It must keep
      // resolving over GraphQL exactly as it always has.
      final routePath = await parse(
        '/file/$fileId/view?$fileKeyQueryParamName=$validFileKey',
      );

      expect(routePath.sharedFileLinkPayload, isNull);
      expect(routePath.sharedRawFileKey, validFileKey);
    });
  });

  group('shared file routes, v2 payload', () {
    // The keyless private link of the design plan §1.3, on the Phase 1 hash
    // route.
    const v2Link = '/file/$fileId/view?v=2&dtx=$dataTxId&mtx=$metadataTxId'
        '&own=$ownerAddress&n=Q3%20Report.pdf&s=4821133'
        '&ct=application%2Fpdf&c=AES256-GCM&iv=$cipherIv';

    test('parses the payload of a keyless private link', () async {
      final routePath = await parse(v2Link);

      expect(routePath.sharedFileId, fileId);

      final payload = routePath.sharedFileLinkPayload;

      expect(payload, isNotNull);
      expect(payload!.dataTxId, dataTxId);
      expect(payload.metadataTxId, metadataTxId);
      expect(payload.ownerAddress, ownerAddress);
      expect(payload.name, 'Q3 Report.pdf');
      expect(payload.size, 4821133);
      expect(payload.contentType, 'application/pdf');
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.cipherIv, cipherIv);
      expect(payload.isPinned, isFalse);
      expect(payload.detailsAreHidden, isFalse);

      // Keyless is the default for a private link: the key travels separately.
      expect(routePath.sharedFileKey, isNull);
      expect(routePath.sharedFileKeyIsDamaged, isFalse);
    });

    test('one malformed field never costs the rest of the payload', () async {
      final routePath = await parse('$v2Link&s=four%20million');

      final payload = routePath.sharedFileLinkPayload;

      expect(payload, isNotNull);
      expect(payload!.size, isNull);
      expect(payload.dataTxId, dataTxId);
      expect(payload.name, 'Q3 Report.pdf');
    });

    test('takes the key from the v2 parameter', () async {
      final routePath = await parse('$v2Link&k=$validFileKey');

      expect(routePath.sharedRawFileKey, validFileKey);
      expect(routePath.sharedFileKey, isNotNull);
      expect(routePath.sharedFileKeyIsDamaged, isFalse);
      expect(
        routePath.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.query,
      );
    });

    test('a fragment key wins over the v2 parameter', () async {
      final routePath = await parse(
        '$v2Link&k=$validDriveKey#k=$validFileKey',
      );

      expect(routePath.sharedRawFileKey, validFileKey);
      expect(
        routePath.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.fragment,
      );
    });

    test('the v2 parameter wins over a legacy key', () async {
      final routePath = await parse(
        '$v2Link&k=$validFileKey&$fileKeyQueryParamName=$validDriveKey',
      );

      expect(routePath.sharedRawFileKey, validFileKey);
      expect(
        routePath.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.query,
      );
    });

    test('a legacy key is still honored on a v2 link', () async {
      final routePath = await parse(
        '$v2Link&$fileKeyQueryParamName=$validFileKey',
      );

      expect(routePath.sharedRawFileKey, validFileKey);
      expect(routePath.sharedFileKey, isNotNull);
      expect(
        routePath.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.legacyQuery,
      );
    });

    test('a damaged key keeps the payload and flags the damage', () async {
      final routePath = await parse(
        '$v2Link&k=${validFileKey.substring(0, 41)}',
      );

      // The page can still show what is being unlocked, and can say the link
      // was damaged rather than silently asking for a key.
      expect(routePath.sharedFileLinkPayload, isNotNull);
      expect(routePath.sharedFileLinkPayload!.name, 'Q3 Report.pdf');
      expect(routePath.sharedFileKey, isNull);
      expect(routePath.sharedRawFileKey, isNull);
      expect(routePath.sharedFileKeyIsDamaged, isTrue);
    });

    test('a damaged fragment key is not replaced by a lower source', () async {
      final routePath = await parse(
        '$v2Link&$fileKeyQueryParamName=$validFileKey'
        '#k=${validDriveKey.substring(0, 41)}',
      );

      expect(routePath.sharedFileKeyIsDamaged, isTrue);
      expect(routePath.sharedRawFileKey, isNull);
    });

    test('a link where nothing is well formed still resolves', () async {
      final routePath = await parse(
        '/file/$fileId/view?v=2&dtx=!&mtx=!&own=!&s=nope&c=ROT13&iv=!'
        '&pin=maybe&hid=maybe&k=nope&unknown=ignored',
      );

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileLinkPayload, isNotNull);
      expect(routePath.sharedFileLinkPayload!.dataTxId, isNull);
      expect(routePath.sharedFileLinkPayload!.isPinned, isFalse);
      expect(routePath.sharedFileKeyIsDamaged, isTrue);
    });

    test('an unsupported version falls back to the v1 path', () async {
      final routePath = await parse(
        '${v2Link.replaceFirst('?v=2', '?v=9')}'
        '&$fileKeyQueryParamName=$validFileKey',
      );

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileLinkPayload, isNull);
      // The key is resolved for v1 links by the same code path.
      expect(routePath.sharedRawFileKey, validFileKey);
    });
  });

  group('restoreRouteInformation', () {
    Future<AppRoutePath> roundTrip(AppRoutePath routePath) async {
      final restored = parser.restoreRouteInformation(routePath);

      return parser.parseRouteInformation(restored);
    }

    test('a v1 link keeps the shape it has always had', () async {
      final routePath = await parse(
        '/file/$fileId/view?$fileKeyQueryParamName=$validFileKey',
      );

      expect(
        parser.restoreRouteInformation(routePath).uri.toString(),
        '/file/$fileId/view?$fileKeyQueryParamName=$validFileKey',
      );
    });

    test('a keyless v1 link restores to the bare path', () async {
      final routePath = await parse('/file/$fileId/view');

      expect(
        parser.restoreRouteInformation(routePath).uri.toString(),
        '/file/$fileId/view',
      );
    });

    test('a v2 payload survives a round trip', () async {
      final routePath = await parse(
        '/file/$fileId/view?v=2&pin=1&hid=1&dtx=$dataTxId&mtx=$metadataTxId'
        '&own=$ownerAddress&n=Q3%20Report.pdf&s=4821133'
        '&ct=application%2Fpdf&c=AES256-CTR&iv=$cipherIv'
        '&k=$validFileKey',
      );

      final restored = await roundTrip(routePath);

      expect(restored.sharedFileId, routePath.sharedFileId);
      expect(
        restored.sharedFileLinkPayload,
        routePath.sharedFileLinkPayload,
      );
      expect(restored.sharedRawFileKey, validFileKey);
      expect(restored.sharedFileKeyIsDamaged, isFalse);
    });

    test('the restored key never lands anywhere a server would see', () async {
      final routePath = await parse('/file/$fileId/view?v=2&k=$validFileKey');

      final location = parser.restoreRouteInformation(routePath).uri.toString();

      // Everything this returns lands after the `#` of the hash route, so the
      // whole location is client-side; what must never happen is the key
      // moving into the path segment, where a future path route would send it.
      expect(location, startsWith('/file/$fileId/view?'));
      expect(location.split('?').first, isNot(contains(validFileKey)));
    });

    test('a drive link still round trips', () async {
      final routePath = await parse(
        '/drives/$driveId?name=My%20Drive'
        '&$driveKeyQueryParamName=$validDriveKey',
      );

      final restored = await roundTrip(routePath);

      expect(restored.driveId, driveId);
      expect(restored.driveName, 'My Drive');
      expect(restored.sharedRawDriveKey, validDriveKey);
    });

    test('a folder link still round trips', () async {
      final routePath = await parse('/drives/$driveId/folders/$folderId');

      final restored = await roundTrip(routePath);

      expect(restored.driveId, driveId);
      expect(restored.driveFolderId, folderId);
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
