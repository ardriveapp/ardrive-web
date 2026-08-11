import 'package:ardrive/models/models.dart';
import 'package:ardrive/utils/app_url_strategy.dart';
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

      test('the hash route is what a link is rooted at by default', () {
        // Byte for byte what ArDrive has always produced. The default URL
        // strategy is hash routing and nothing about that has moved.
        expect(
          generatePublicFileShareLink(fileId: testFile.id).toString(),
          'https://app.ardrive.io/#/file/${testFile.id}/view',
        );
      });

      test('a public file link is rooted at /share under path routing', () {
        expect(
          generatePublicFileShareLink(
            fileId: testFile.id,
            strategy: AppUrlStrategy.path,
          ).toString(),
          'https://app.ardrive.io/share/${testFile.id}',
        );
      });

      test('a private file link puts the key in the fragment under path '
          'routing', () async {
        // `?fileKey=` is safe on the hash route and only there: on a path
        // route the query is sent to the server.
        final link = await generatePrivateFileShareLink(
          fileId: testFile.id,
          fileKey: testFileKey,
          strategy: AppUrlStrategy.path,
        );

        expect(
          link.toString(),
          'https://app.ardrive.io/share/${testFile.id}#k=$testFileKeyBase64',
        );
        expect(link.toString(), isNot(contains('fileKey')));
        expect(
          link.toString().split('#').first,
          isNot(contains(testFileKeyBase64)),
        );
      });

      test('a private file link keeps its v1 shape under hash routing',
          () async {
        final link = await generatePrivateFileShareLink(
          fileId: testFile.id,
          fileKey: testFileKey,
        );

        expect(
          link.toString(),
          'https://app.ardrive.io/#/file/${testFile.id}/view'
          '?fileKey=$testFileKeyBase64',
        );
      });
    });

    group('drive share links are unaffected by the URL strategy', () {
      // Drive links stay on the hash route this cycle (§1.1) - which is also
      // what keeps them working once path routing is switched on, since the
      // route parser resolves a route that arrives inside the fragment.
      test('a public drive link is still a hash link', () {
        expect(
          generatePublicDriveShareLink(
            driveId: 'driveId',
            driveName: 'My Drive',
          ).toString(),
          'https://app.ardrive.io/#/drives/driveId?name=My+Drive',
        );
      });

      test('a private drive link still carries its key in the query', () async {
        const driveKeyBase64 = 'X123YZAB-CD4e5fgHIjKlmN6O7pqrStuVwxYzaBcd8E';

        final link = await generatePrivateDriveShareLink(
          driveId: 'driveId',
          driveName: 'My Drive',
          driveKey: SecretKey(decodeBase64ToBytes(driveKeyBase64)),
        );

        expect(link.toString(), startsWith('https://app.ardrive.io/#/drives/'));
        expect(link.toString(), endsWith('&driveKey=$driveKeyBase64'));
      });
    });

    group('v2 file share link generator tests', () {
      // The ids of the design plan's example links, §1.3. Every Arweave id is
      // 43 base64url characters *that decode to 32 bytes* - see
      // [isCanonical32ByteId], and the note in
      // `test/utils/shared_file_link_test.dart` about why that second half
      // matters now.
      const fileId = '8f3c2a10-6f4e-4c7a-9b2e-1d2f3a4b5c6d';
      const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeQ';
      const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
      const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';
      const bundledInTxId = 'oLd7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWc';
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

      /// What a link should assert, as the payload a reader gets back.
      SharedFileLinkPayload expectedPayload({
        bool isPrivate = false,
        bool isPinned = false,
        bool detailsAreHidden = false,
        String? key,
        SharedFileLinkKeySource keySource = SharedFileLinkKeySource.query,
      }) =>
          SharedFileLinkPayload(
            dataTxId: dataTxId,
            metadataTxId: metadataTxId,
            ownerAddress: ownerAddress,
            name: detailsAreHidden ? null : fileName,
            size: detailsAreHidden ? null : fileSize,
            contentType: detailsAreHidden ? null : contentType,
            cipher: isPrivate ? Cipher.aes256gcm : null,
            cipherIv: isPrivate ? cipherIv : null,
            isPinned: isPinned,
            detailsAreHidden: detailsAreHidden,
            key: key == null
                ? SharedFileLinkKey.absent
                : SharedFileLinkKey.parse(key, source: keySource),
          );

      /// The payload [link] actually carries, read back out of it.
      SharedFileLinkPayload payloadOf(Uri link) {
        final payload = SharedFileLinkPayload.tryParse(locationOf(link));

        expect(payload, isNotNull, reason: 'no payload in $link');

        return payload!;
      }

      test('a public file link carries every locally known field and no key',
          () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload(),
        );

        final location = locationOf(link);

        expect(link.toString(), startsWith('https://app.ardrive.io/#/file/'));
        expect(location.path, '/file/$fileId/view');
        expect(payloadOf(link), expectedPayload());
        expect(
          location.queryParameters.keys,
          [SharedFileLinkParams.payload],
          reason: 'a v2 link is one packed parameter and, at most, a key',
        );
        expect(location.fragment, isEmpty);
      });

      test('a public file link never has to escape the file name', () {
        // The name is bytes inside base64url now, so a space - or a `&`, or a
        // `#` - is no longer one character away from ending the query.
        const awkward = 'Q3 & Q4 #final.pdf';
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload().copyWith(name: awkward),
        );

        expect(
          locationOf(link).query,
          matches(RegExp(r'^d=[A-Za-z0-9_-]+$')),
        );
        expect(link.toString(), isNot(contains('%')));
        expect(link.toString(), isNot(contains(awkward)));
        expect(payloadOf(link).name, awkward);
      });

      test('a private file link is keyless by default', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(),
        );

        expect(payloadOf(link), expectedPayload(isPrivate: true));
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

        expect(payloadOf(link), expectedPayload(isPrivate: true));
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
          payloadOf(link),
          expectedPayload(isPrivate: true, key: fileKeyBase64),
        );
        expect(
          locationOf(link).queryParameters[SharedFileLinkParams.key],
          fileKeyBase64,
        );
        // The whole query sits after the `#`, so the key is never sent to a
        // server even in this position.
        expect(link.toString(), contains('/#/file/'));
        expect(locationOf(link).fragment, isEmpty);
      });

      test('places the key in a fragment on a path route', () {
        // The placement the whole `#k=` design is for: on a path route the
        // app has not spent the URL's one fragment, and the query is sent to
        // the server, so the fragment is the only position left.
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(),
          rawFileKey: fileKeyBase64,
          strategy: AppUrlStrategy.path,
        );

        expect(link.toString(), startsWith('https://app.ardrive.io/share/'));
        expect(link.toString(), endsWith('#k=$fileKeyBase64'));
        expect(link.path, '/share/$fileId');
        expect(link.fragment, 'k=$fileKeyBase64');
        expect(
          SharedFileLinkPayload.tryParse(link),
          expectedPayload(
            isPrivate: true,
            key: fileKeyBase64,
            keySource: SharedFileLinkKeySource.fragment,
          ),
        );
        // The half of the URL a server is sent carries no key.
        expect(
          link.toString().split('#').first,
          isNot(contains(fileKeyBase64)),
        );
      });

      test('a path route link is not prefixed with the hash route', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: publicPayload(),
          strategy: AppUrlStrategy.path,
        );

        expect(link.toString(), isNot(contains('/#')));
        expect(link.path, '/share/$fileId');
        expect(SharedFileLinkPayload.tryParse(link), expectedPayload());
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

        // The refusal is about the hash route, not about the placement: the
        // identical call is correct once the app is served on a path route.
        expect(
          () => generateFileShareLinkV2(
            fileId: fileId,
            payload: privatePayload(),
            rawFileKey: fileKeyBase64,
            keyPlacement: SharedFileLinkKeyPlacement.fragment,
            strategy: AppUrlStrategy.path,
          ),
          returnsNormally,
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

        expect(payloadOf(link), expectedPayload(isPrivate: true));
      });

      test('a pinned link sets pin and keeps every other field', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(isPinned: true),
        );

        expect(
          payloadOf(link),
          expectedPayload(isPrivate: true, isPinned: true),
        );
      });

      test('a hidden link sets hid and omits n, s and ct', () {
        final link = generateFileShareLinkV2(
          fileId: fileId,
          payload: privatePayload(detailsAreHidden: true),
        );

        final payload = payloadOf(link);

        expect(
          payload,
          expectedPayload(isPrivate: true, detailsAreHidden: true),
        );
        expect(payload.name, isNull);
        expect(payload.size, isNull);
        expect(payload.contentType, isNull);
        expect(payload.detailsAreHidden, isTrue);
        // Not even in an encoding a reader could undo: the bytes are not there.
        expect(link.toString(), isNot(contains('Report')));
        expect(
          payload.encode().length,
          lessThan(privatePayload().encode().length),
        );
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

        // A dropped `n` is what an untruncated name would have cost us.
        final name = payloadOf(link).name;

        expect(name, hasLength(SharedFileLinkPayload.maxNameLength));
        expect(
          name,
          longName.substring(0, SharedFileLinkPayload.maxNameLength),
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

      // The whole point of packing the payload was that the readable schema
      // produced links that chat clients truncate, mail clients wrap and QR
      // encoders inflate. That is a claim about a number, so the number is
      // asserted rather than described - and when a new field moves it, the
      // person adding the field is the one who gets to decide whether the
      // trade is worth it.
      //
      // The readable schema's lengths, for the same four links, were 268 /
      // 301 / 347 / 264. Everything below is measured against those.
      group('the length of a link', () {
        test('a public link is 232 characters, down from 268', () {
          expect(
            generateFileShareLinkV2(fileId: fileId, payload: publicPayload())
                .toString(),
            hasLength(232),
          );
        });

        test('a private keyless link is 248 characters, down from 301', () {
          expect(
            generateFileShareLinkV2(fileId: fileId, payload: privatePayload())
                .toString(),
            hasLength(248),
          );
        });

        test('a private link with the key is 294 characters, down from 347',
            () {
          expect(
            generateFileShareLinkV2(
              fileId: fileId,
              payload: privatePayload(),
              rawFileKey: fileKeyBase64,
            ).toString(),
            hasLength(294),
          );
        });

        test('a pinned, hidden link is 222 characters, down from 264', () {
          expect(
            generateFileShareLinkV2(
              fileId: fileId,
              payload: privatePayload(isPinned: true, detailsAreHidden: true),
            ).toString(),
            hasLength(222),
          );
        });

        test('the fixed cost of a link is the route, not the payload', () {
          // 71 of those characters are the origin and the route, which no
          // encoding can touch: `https://app.ardrive.io/#/file/{uuid}/view`.
          // The next lever is not a denser payload - base64url of raw bytes is
          // already exactly as dense as a 43 character id - it is one fewer id
          // in the link. See §1.2.
          final route = generatePublicFileShareLink(fileId: fileId).toString();

          expect(route, hasLength(71));
          expect(
            generateFileShareLinkV2(fileId: fileId, payload: publicPayload())
                .toString()
                .length,
            route.length + '?d='.length + 158,
            reason: 'the payload of a public link is 118 bytes',
          );
        });
      });
    });
  });
}
