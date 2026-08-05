import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/link_generators.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('link generators tests', () {
    group('drive share link generator tests', () {
      late Drive testPublicDrive;
      late Drive testPrivateDrive;
      late String testPrivateDriveKeyBase64;
      late SecretKey testPrivateDriveKey;
      setUp(() {
        testPublicDrive = Drive(
          id: 'publicDriveId',
          rootFolderId: 'publicDriveRootFolderId',
          ownerAddress: 'ownerAddress',
          name: 'testPublicDrive',
          privacy: DrivePrivacyTag.public,
          dateCreated: DateTime.now(),
          lastUpdated: DateTime.now(),
          isHidden: false,
        );
        testPrivateDrive = Drive(
          id: 'privateDriveId',
          rootFolderId: 'privateRootFolderId',
          ownerAddress: 'ownerAddress',
          name: 'testPrivateDrive',
          privacy: DrivePrivacyTag.private,
          dateCreated: DateTime.now(),
          lastUpdated: DateTime.now(),
          isHidden: false,
        );
        testPrivateDriveKeyBase64 =
            'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E';
        testPrivateDriveKey =
            SecretKey(decodeBase64ToBytes(testPrivateDriveKeyBase64));
      });
      test(
          'generatePrivateDriveShareLink generates the correct link for a private drive',
          () async {
        final webShareUri = await generatePrivateDriveShareLink(
          driveId: testPrivateDrive.id,
          driveName: testPrivateDrive.name,
          driveKey: testPrivateDriveKey,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final driveShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final driveId = driveShareLink.pathSegments.last;
        final driveName = driveShareLink.queryParameters['name'];
        final driveKey = driveShareLink.queryParameters['driveKey'];

        expect(driveId, equals(testPrivateDrive.id));
        expect(driveName, equals(testPrivateDrive.name));
        expect(driveKey, equals(testPrivateDriveKeyBase64));
      });
      test(
          'generatePublicDriveShareLink generates the correct link for a public drive',
          () async {
        final webShareUri = generatePublicDriveShareLink(
          driveId: testPublicDrive.id,
          driveName: testPublicDrive.name,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final driveShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final driveId = driveShareLink.pathSegments.last;
        final driveName = driveShareLink.queryParameters['name'];

        expect(driveId, equals(testPublicDrive.id));
        expect(driveName, equals(testPublicDrive.name));
      });
    });

    group('file share link generator tests', () {
      late FileEntry testFile;
      late String testFileKeyBase64;
      late SecretKey testFileKey;
      setUp(() {
        testFile = FileEntry(
          id: 'testFileId',
          driveId: 'driveId',
          parentFolderId: 'parentFolderId',
          name: 'testFile',
          dataTxId: 'Data',
          size: 500,
          dateCreated: DateTime.now(),
          lastModifiedDate: DateTime.now(),
          lastUpdated: DateTime.now(),
          dataContentType: '',
          isHidden: false,
          path: '',
        );
        testFileKeyBase64 = 'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E';
        testFileKey = SecretKey(decodeBase64ToBytes(testFileKeyBase64));
      });
      test(
          'generatePrivateFileShareLink generates the correct link for a private file',
          () async {
        final webShareUri = await generatePrivateFileShareLink(
          fileId: testFile.id,
          fileKey: testFileKey,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final fileShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final fileId = fileShareLink.pathSegments[1];
        final fileKey = fileShareLink.queryParameters['fileKey'];

        expect(fileId, equals(testFile.id));
        expect(fileKey, equals(testFileKeyBase64));
      });
      test('generateFileShareLink generates the correct link for a public file',
          () async {
        final webShareUri = generatePublicFileShareLink(
          fileId: testFile.id,
        );
        // Remove # delimiter as it messes with Uri parsing outside of app route
        // information parser
        final fileShareLink = Uri.parse(
          webShareUri.toString().replaceAll('/#', ''),
        );
        final fileId = fileShareLink.pathSegments[1];

        expect(fileId, equals(testFile.id));
      });
    });

    group('v2 file share link generator tests', () {
      // The ids of the design plan's example links, §1.3. Every Arweave id is
      // 43 base64url characters.
      const fileId = '8f3c2a10-6f4e-4c7a-9b2e-1d2f3a4b5c6d';
      const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
      const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
      const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';
      const bundledInTxId = 'oLd7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWe';
      const thumbnailTxId = 'oLdzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBn0';

      // 12 IV bytes are 16 base64url characters.
      const cipherIv = '9tR2kX0pLmQz8sQ1';

      // 43 base64url characters whose last character carries only 4
      // significant bits, so its low 2 bits are zero - see
      // [SharedFileLinkKey.isWellFormed].
      const fileKeyBase64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

      const fileName = 'Q3 Report.pdf';
      const fileSize = 4821133;
      const contentType = 'application/pdf';

      /// Everything a share of a *public* file knows locally.
      SharedFileLinkPayload publicPayload({
        bool isPinned = false,
        bool detailsAreHidden = false,
      }) =>
          SharedFileLinkPayload(
            dataTxId: dataTxId,
            metadataTxId: metadataTxId,
            ownerAddress: ownerAddress,
            name: detailsAreHidden ? null : fileName,
            size: detailsAreHidden ? null : fileSize,
            contentType: detailsAreHidden ? null : contentType,
            isPinned: isPinned,
            detailsAreHidden: detailsAreHidden,
          );

      /// The same, for a private file whose cipher details resolved.
      SharedFileLinkPayload privatePayload({
        bool isPinned = false,
        bool detailsAreHidden = false,
        SharedFileLinkKey? key,
      }) =>
          publicPayload(
            isPinned: isPinned,
            detailsAreHidden: detailsAreHidden,
          ).copyWith(
            cipher: Cipher.aes256gcm,
            cipherIv: cipherIv,
            key: key,
          );

      /// The route location of [link] - the part after the `#`, which is where
      /// the query of a hash route lives and the only part [Uri] will parse as
      /// a query.
      Uri locationOf(Uri link) =>
          Uri.parse(link.toString().replaceFirst('/#', ''));

      Map<String, String> expectedParameters({
        bool isPrivate = false,
        bool isPinned = false,
        bool detailsAreHidden = false,
        String? key,
      }) =>
          {
            SharedFileLinkParams.version: '2',
            if (isPinned) SharedFileLinkParams.pinned: '1',
            if (detailsAreHidden) SharedFileLinkParams.hidden: '1',
            SharedFileLinkParams.dataTxId: dataTxId,
            SharedFileLinkParams.metadataTxId: metadataTxId,
            SharedFileLinkParams.owner: ownerAddress,
            if (!detailsAreHidden) SharedFileLinkParams.name: fileName,
            if (!detailsAreHidden) SharedFileLinkParams.size: '$fileSize',
            if (!detailsAreHidden)
              SharedFileLinkParams.contentType: contentType,
            if (isPrivate) SharedFileLinkParams.cipher: Cipher.aes256gcm,
            if (isPrivate) SharedFileLinkParams.cipherIv: cipherIv,
            if (key != null) SharedFileLinkParams.key: key,
          };

      test('a public file link carries every locally known field and no key',
          () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload(),
        );

        final location = locationOf(link);

        expect(link.toString(), startsWith('https://app.ardrive.io/#/file/'));
        expect(location.path, '/file/$fileId/view');
        expect(location.queryParameters, expectedParameters());
        expect(location.fragment, isEmpty);
      });

      test('a public file link percent encodes the file name', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload(),
        );

        expect(link.toString(), contains('n=Q3%20Report.pdf'));
      });

      test('a private file link is keyless by default', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(),
        );

        expect(
          locationOf(link).queryParameters,
          expectedParameters(isPrivate: true),
        );
        expect(link.toString(), isNot(contains(fileKeyBase64)));
      });

      test('a key on the payload never travels unless it is passed in', () {
        // The dialog holds a key for the file it is sharing; nothing but the
        // opt-in may put it in a link.
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(
            key: SharedFileLinkKey.parse(
              fileKeyBase64,
              source: SharedFileLinkKeySource.query,
            ),
          ),
        );

        expect(
          locationOf(link).queryParameters,
          expectedParameters(isPrivate: true),
        );
        expect(
          locationOf(link).queryParameters,
          isNot(contains(SharedFileLinkParams.key)),
        );
        expect(link.toString(), isNot(contains(fileKeyBase64)));
      });

      test('the key-in-link opt-in writes the key into the hash query', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(),
          rawFileKey: fileKeyBase64,
        );

        expect(
          locationOf(link).queryParameters,
          expectedParameters(isPrivate: true, key: fileKeyBase64),
        );
        // The whole query sits after the `#`, so the key is never sent to a
        // server even in this position.
        expect(link.toString(), contains('/#/file/'));
        expect(locationOf(link).fragment, isEmpty);
      });

      test('refuses to place the key in a fragment on the hash route', () {
        // The hash route has already spent the URL's one fragment. Emitting a
        // second `#` does not fail on its own - the key would be percent
        // encoded into the last query parameter's value, which is the one
        // place a key may never travel - so the generator refuses. Phase 3's
        // path routes are what make this placement real.
        expect(
          () => generateFileShareLinkV2(
            fileId: fileId,
            payload: privatePayload(),
            rawFileKey: fileKeyBase64,
            keyPlacement: SharedFileLinkKeyPlacement.fragment,
          ),
          throwsUnsupportedError,
        );
      });

      test('a fragment placement without a key is harmless', () {
        // Nothing to misplace, so the public link builds normally.
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload(),
          keyPlacement: SharedFileLinkKeyPlacement.fragment,
        );

        expect(locationOf(link).fragment, isEmpty);
      });

      test('an empty key is no key at all', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(),
          rawFileKey: '',
        );

        expect(
          locationOf(link).queryParameters,
          expectedParameters(isPrivate: true),
        );
      });

      test('a pinned link sets pin and keeps every other field', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(isPinned: true),
        );

        expect(
          locationOf(link).queryParameters,
          expectedParameters(isPrivate: true, isPinned: true),
        );
      });

      test('a hidden link sets hid and omits n, s and ct', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(detailsAreHidden: true),
        );

        final parameters = locationOf(link).queryParameters;

        expect(
          parameters,
          expectedParameters(isPrivate: true, detailsAreHidden: true),
        );
        expect(parameters.containsKey(SharedFileLinkParams.name), isFalse);
        expect(parameters.containsKey(SharedFileLinkParams.size), isFalse);
        expect(
          parameters.containsKey(SharedFileLinkParams.contentType),
          isFalse,
        );
        expect(link.toString(), isNot(contains('Report')));
      });

      test('a link without cipher details is still a usable v2 link', () {
        // What the sharer gets when the one `getTransactionDetails` call fails.
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload(),
        );

        final payload = SharedFileLinkPayload.tryParse(locationOf(link));

        expect(payload, isNotNull);
        expect(payload!.hasFastPathTarget, isTrue);
        expect(payload.hasCipherDetails, isFalse);
        expect(payload.dataTxId, dataTxId);
        expect(payload.name, fileName);
      });

      test('a long file name is truncated to what the parser will accept', () {
        final longName = '${'a' * 200}.pdf';

        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload().copyWith(name: longName),
        );

        final name =
            locationOf(link).queryParameters[SharedFileLinkParams.name];

        expect(name, hasLength(SharedFileLinkPayload.maxNameLength));
        expect(name, longName.substring(0, SharedFileLinkPayload.maxNameLength));
        // A dropped `n` is what an untruncated name would have cost us.
        expect(
          SharedFileLinkPayload.tryParse(locationOf(link))?.name,
          isNotNull,
        );
      });

      test('every field survives a round trip through the parser', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(isPinned: true).copyWith(
            bundledInTxId: bundledInTxId,
            thumbnailTxId: thumbnailTxId,
          ),
          rawFileKey: fileKeyBase64,
        );

        final payload = SharedFileLinkPayload.tryParse(locationOf(link))!;

        expect(payload.version, SharedFileLinkPayload.currentVersion);
        expect(payload.dataTxId, dataTxId);
        expect(payload.metadataTxId, metadataTxId);
        expect(payload.ownerAddress, ownerAddress);
        expect(payload.name, fileName);
        expect(payload.size, fileSize);
        expect(payload.contentType, contentType);
        expect(payload.cipher, Cipher.aes256gcm);
        expect(payload.cipherIv, cipherIv);
        expect(payload.isPinned, isTrue);
        expect(payload.bundledInTxId, bundledInTxId);
        expect(payload.thumbnailTxId, thumbnailTxId);
        expect(payload.detailsAreHidden, isFalse);
        expect(payload.key.raw, fileKeyBase64);
        expect(payload.key.isUsable, isTrue);
      });
    });
  });
}
