import 'package:ardrive/pages/pages.dart';
import 'package:ardrive/utils/app_url_strategy.dart';
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

  // 43 base64url characters that decode to 32 bytes: the shape of every
  // Arweave id, and the same canonicality rule the keys above follow. A v2
  // payload stores ids as bytes, so an id that will not decode cannot travel.
  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeQ';
  const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';

  // 12 IV bytes, base64url encoded.
  const cipherIv = '9tR2kX0pLmQz8sQ1';

  /// The keyless private link of the design plan §1.3, as a payload.
  const sharedPayload = SharedFileLinkPayload(
    dataTxId: dataTxId,
    metadataTxId: metadataTxId,
    ownerAddress: ownerAddress,
    name: 'Q3 Report.pdf',
    size: 4821133,
    contentType: 'application/pdf',
    cipher: Cipher.aes256gcm,
    cipherIv: cipherIv,
  );

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
    // route. Built through the builder rather than typed out: the payload is
    // packed, and a hand-written one here would only be testing this file's
    // arithmetic. `test/utils/shared_file_link_test.dart` is where the layout
    // itself is pinned.
    final v2Link =
        buildSharedFileLinkLocation(fileId: fileId, payload: sharedPayload);

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

    test('a field that cannot be encoded never costs the rest', () async {
      // A size the payload cannot spell - eight bytes where the schema carries
      // six - reached by rebuilding the link around it. The field-by-field
      // corruption matrix lives with the layout, in
      // `test/utils/shared_file_link_test.dart`; what this asserts is that the
      // route parser sees the same partial payload the decoder produces.
      final routePath = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: sharedPayload.copyWith(size: 1 << 60),
        ),
      );

      final payload = routePath.sharedFileLinkPayload;

      expect(payload, isNotNull);
      expect(payload!.size, isNull);
      expect(payload.dataTxId, dataTxId);
      expect(payload.name, 'Q3 Report.pdf');
      expect(payload.contentType, 'application/pdf');
    });

    test('a payload cut in transit still names the file to fetch', () async {
      // What a chat client does to a long link. The reader keeps the fields
      // before the cut, and `dtx` - the one that starts the download - is
      // first in the layout for exactly this reason.
      final cut = v2Link.substring(0, v2Link.indexOf('?d=') + 3 + 48);
      final routePath = await parse(cut);

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileLinkPayload, isNotNull);
      expect(routePath.sharedFileLinkPayload!.dataTxId, dataTxId);
      expect(routePath.sharedFileLinkPayload!.name, isNull);
      expect(routePath.sharedFileLinkPayload!.cipher, Cipher.aes256gcm);
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

    test('a payload that is not a payload still resolves the route', () async {
      // A `d` nothing can read is a link with no payload, which is a v1 link:
      // the file resolves over GraphQL, and the route and the key damage are
      // reported exactly as they would be on any other link.
      final routePath = await parse(
        '/file/$fileId/view?d=not%20a%20payload!&k=nope&unknown=ignored',
      );

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileLinkPayload, isNull);
      expect(routePath.sharedFileKeyIsDamaged, isTrue);
      expect(routePath.sharedRawFileKey, isNull);
    });

    test('an oversized payload never reaches the decoder', () async {
      final oversized = 'A' * (SharedFileLinkPayload.maxEncodedLength + 1);
      final routePath = await parse('/file/$fileId/view?d=$oversized');

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileLinkPayload, isNull);
    });

    test('an unsupported version falls back to the v1 path', () async {
      // A v3 link read by a v2 build. Everything is resolved from the chain,
      // which cannot be wrong about anything the link asserted.
      final future = sharedPayload.copyWith(version: 9).encode();
      final routePath = await parse(
        '/file/$fileId/view?d=$future'
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
      // Every field at once, pinned and hidden, with the second cipher and a
      // key: what has to come back out of the address bar unchanged.
      final routePath = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: sharedPayload.copyWith(
            isPinned: true,
            detailsAreHidden: true,
            cipher: Cipher.aes256ctr,
          ),
          rawFileKey: validFileKey,
        ),
      );

      final restored = await roundTrip(routePath);

      expect(restored.sharedFileId, routePath.sharedFileId);
      expect(
        restored.sharedFileLinkPayload,
        routePath.sharedFileLinkPayload,
      );
      expect(restored.sharedFileLinkPayload!.isPinned, isTrue);
      expect(restored.sharedFileLinkPayload!.detailsAreHidden, isTrue);
      expect(restored.sharedFileLinkPayload!.cipher, Cipher.aes256ctr);
      expect(restored.sharedRawFileKey, validFileKey);
      expect(restored.sharedFileKeyIsDamaged, isFalse);
    });

    test('the restored key never lands anywhere a server would see', () async {
      final routePath = await parse(
        '/file/$fileId/view'
        '?d=${const SharedFileLinkPayload().encode()}&k=$validFileKey',
      );

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

  group('raw transaction routes', () {
    test('parses a bare transaction link', () async {
      final routePath = await parse('/view/$dataTxId');

      expect(routePath.rawTransactionId, dataTxId);
      expect(routePath.rawTransactionName, isNull);
      expect(routePath.rawTransactionContentType, isNull);
      // Nothing about a `/view` link says anything about a file.
      expect(routePath.sharedFileId, isNull);
      expect(routePath.driveId, isNull);
    });

    test('parses the name and content type hints', () async {
      final routePath =
          await parse('/view/$dataTxId?n=talk.mp4&ct=video%2Fmp4');

      expect(routePath.rawTransactionId, dataTxId);
      expect(routePath.rawTransactionName, 'talk.mp4');
      expect(routePath.rawTransactionContentType, 'video/mp4');
    });

    test('drops a hint the shared file schema would drop', () async {
      // Same fields, same validation (§1.3): a hint is never worth failing a
      // route over, and never worth trusting when it is malformed.
      final routePath = await parse(
        '/view/$dataTxId?n=${'a' * 200}&ct=not-a-mime-type',
      );

      expect(routePath.rawTransactionId, dataTxId);
      expect(routePath.rawTransactionName, isNull);
      expect(routePath.rawTransactionContentType, isNull);
    });

    test('rejects an id that is not a transaction id', () async {
      // The id is the whole route; one that addresses nothing has no page.
      final routePath = await parse('/view/not-a-transaction-id');

      expect(routePath.rawTransactionId, isNull);
      expect(routePath.sharedFileId, isNull);
    });

    test('is exactly two segments long', () async {
      expect((await parse('/view')).rawTransactionId, isNull);
      expect((await parse('/view/$dataTxId/extra')).rawTransactionId, isNull);
    });
  });

  group('routes under both URL strategies', () {
    // Everything below is asserted twice: once for the location the hash
    // strategy hands the router (everything after the first `#`), and once for
    // the location the path strategy hands it (`pathname + search + hash`).
    // The default strategy's behavior must not move, and the other one must
    // reach the same route paths.

    /// The router location of a link written on the hash route, as seen under
    /// [strategy]. Under path routing the host only ever saw `/`, so the whole
    /// route arrives inside the fragment.
    String hashLinkLocation(String route, AppUrlStrategy strategy) =>
        strategy == AppUrlStrategy.path ? '/#$route' : route;

    const payload = SharedFileLinkPayload(
      dataTxId: dataTxId,
      metadataTxId: metadataTxId,
      ownerAddress: ownerAddress,
      name: 'Q3 Report.pdf',
      size: 4821133,
      contentType: 'application/pdf',
      cipher: Cipher.aes256gcm,
      cipherIv: cipherIv,
    );

    for (final strategy in AppUrlStrategy.values) {
      group(strategy.name, () {
        /// A link as this strategy's generator would write it.
        String canonicalLocation({String? key}) => buildSharedFileLinkLocation(
              fileId: fileId,
              payload: payload,
              rawFileKey: key,
              route: strategy.sharedFileRoute,
              keyPlacement: strategy.fileKeyPlacement,
            );

        test('a v2 payload parses whole', () async {
          final routePath = await parse(canonicalLocation());

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedFileLinkPayload, payload);
        });

        test('a keyed v2 link resolves its key', () async {
          final routePath = await parse(canonicalLocation(key: validFileKey));

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedRawFileKey, validFileKey);
          expect(routePath.sharedFileKey, isNotNull);
          expect(routePath.sharedFileKeyIsDamaged, isFalse);
        });

        test('a legacy link resolves', () async {
          // Permanent links. `/#/file/{fileId}/view?fileKey=...` must work
          // forever, including after the app stops writing that shape.
          final routePath = await parse(
            hashLinkLocation(
              '/file/$fileId/view?$fileKeyQueryParamName=$validFileKey',
              strategy,
            ),
          );

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedRawFileKey, validFileKey);
          expect(routePath.sharedFileKey, isNotNull);
          expect(routePath.sharedFileKeyIsDamaged, isFalse);
          // A legacy link asserts nothing about the file: GraphQL resolution,
          // exactly as it always has been.
          expect(routePath.sharedFileLinkPayload, isNull);
        });

        test('a keyless legacy link resolves', () async {
          final routePath = await parse(
            hashLinkLocation('/file/$fileId/view', strategy),
          );

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedFileKey, isNull);
          expect(routePath.sharedFileKeyIsDamaged, isFalse);
        });

        test('a damaged legacy key is flagged rather than thrown', () async {
          final routePath = await parse(
            hashLinkLocation(
              '/file/$fileId/view'
              '?$fileKeyQueryParamName=${validFileKey.substring(0, 41)}',
              strategy,
            ),
          );

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedFileKey, isNull);
          expect(routePath.sharedFileKeyIsDamaged, isTrue);
        });

        test('an empty legacy key is an absent key, not a damaged one',
            () async {
          final routePath = await parse(
            hashLinkLocation(
              '/file/$fileId/view?$fileKeyQueryParamName=',
              strategy,
            ),
          );

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedFileKeyIsDamaged, isFalse);
        });

        test('a v2 hash link keeps every field it carried', () async {
          // What Phase 1 generated. Under path routing it arrives inside the
          // fragment and is rewritten onto `/share`; nothing may be lost.
          final routePath = await parse(
            hashLinkLocation(
              buildSharedFileLinkLocation(
                fileId: fileId,
                payload: sharedPayload,
                rawFileKey: validFileKey,
              ),
              strategy,
            ),
          );

          expect(routePath.sharedFileId, fileId);
          expect(routePath.sharedFileLinkPayload?.dataTxId, dataTxId);
          expect(routePath.sharedFileLinkPayload?.name, 'Q3 Report.pdf');
          expect(routePath.sharedFileLinkPayload?.size, 4821133);
          expect(routePath.sharedFileLinkPayload?.contentType,
              'application/pdf');
          expect(routePath.sharedRawFileKey, validFileKey);
        });

        test('a drive link is unaffected', () async {
          final routePath = await parse(
            hashLinkLocation(
              '/drives/$driveId?name=My%20Drive'
              '&$driveKeyQueryParamName=$validDriveKey',
              strategy,
            ),
          );

          expect(routePath.driveId, driveId);
          expect(routePath.driveName, 'My Drive');
          expect(routePath.sharedDriveKey, isNotNull);
          expect(routePath.sharedRawDriveKey, validDriveKey);
        });

        test('a folder link is unaffected', () async {
          final routePath = await parse(
            hashLinkLocation('/drives/$driveId/folders/$folderId', strategy),
          );

          expect(routePath.driveId, driveId);
          expect(routePath.driveFolderId, folderId);
        });

        test('a raw transaction link parses', () async {
          final routePath = await parse(
            hashLinkLocation('/view/$dataTxId?n=talk.mp4', strategy),
          );

          expect(routePath.rawTransactionId, dataTxId);
          expect(routePath.rawTransactionName, 'talk.mp4');
        });
      });
    }

    test('a v2 payload parses identically from /share and from the hash route',
        () async {
      final fromHashRoute = await parse(
        buildSharedFileLinkLocation(fileId: fileId, payload: payload),
      );
      final fromShareRoute = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: payload,
          route: SharedFileLinkRoute.share,
        ),
      );

      expect(fromShareRoute.sharedFileId, fromHashRoute.sharedFileId);
      expect(
        fromShareRoute.sharedFileLinkPayload,
        fromHashRoute.sharedFileLinkPayload,
      );
    });

    test('a key parses identically from `#k=` and from the hash query',
        () async {
      final fromHashQuery = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: payload,
          rawFileKey: validFileKey,
        ),
      );
      final fromFragment = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: payload,
          rawFileKey: validFileKey,
          route: SharedFileLinkRoute.share,
          keyPlacement: SharedFileLinkKeyPlacement.fragment,
        ),
      );

      expect(fromFragment.sharedRawFileKey, fromHashQuery.sharedRawFileKey);
      expect(fromFragment.sharedFileKeyIsDamaged, isFalse);
      // The one thing that differs is where the key came from, which is
      // exactly what the two strategies are about.
      expect(
        fromFragment.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.fragment,
      );
      expect(
        fromHashQuery.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.query,
      );
    });

    test('the §1.3 example link parses on the /share route', () async {
      final routePath = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: sharedPayload,
          rawFileKey: validFileKey,
          route: SharedFileLinkRoute.share,
          keyPlacement: SharedFileLinkKeyPlacement.fragment,
        ),
      );

      expect(routePath.sharedFileId, fileId);
      expect(routePath.sharedFileLinkPayload!.dataTxId, dataTxId);
      expect(routePath.sharedFileLinkPayload!.name, 'Q3 Report.pdf');
      expect(routePath.sharedRawFileKey, validFileKey);
      expect(
        routePath.sharedFileLinkPayload!.key.source,
        SharedFileLinkKeySource.fragment,
      );
    });

    test('a /share link is exactly two segments long', () async {
      expect((await parse('/share')).sharedFileId, isNull);
      expect((await parse('/share/$fileId/view')).sharedFileId, isNull);
    });
  });

  group('restoreRouteInformation under path routing', () {
    late AppRouteInformationParser pathParser;

    String restore(AppRoutePath routePath) =>
        pathParser.restoreRouteInformation(routePath).uri.toString();

    setUp(() {
      pathParser =
          AppRouteInformationParser(urlStrategy: AppUrlStrategy.path);
    });

    test('a legacy link is written back as /share with the key in the '
        'fragment', () async {
      final routePath = await parse(
        '/file/$fileId/view?$fileKeyQueryParamName=$validFileKey',
      );

      final location = restore(routePath);

      expect(location, '/share/$fileId#k=$validFileKey');
      // The half of the URL a server is sent carries no key.
      expect(location.split('#').first, isNot(contains(validFileKey)));
    });

    test('a v2 link keeps its payload in the query and its key out of it',
        () async {
      final routePath = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: sharedPayload,
          rawFileKey: validFileKey,
        ),
      );

      final location = restore(routePath);

      expect(
        location,
        startsWith('/share/$fileId?${SharedFileLinkParams.payload}='),
      );
      expect(location, endsWith('#k=$validFileKey'));
      expect(location.split('#').first, isNot(contains(validFileKey)));
      // The payload made the move whole, not just the route.
      expect(
        SharedFileLinkPayload.tryParse(Uri.parse(location))?.dataTxId,
        dataTxId,
      );
    });

    test('a keyless link restores to the bare route', () async {
      final routePath = await parse('/file/$fileId/view');

      expect(restore(routePath), '/share/$fileId');
    });

    test('a raw transaction link restores with its hints', () async {
      final routePath = await parse('/view/$dataTxId?n=talk.mp4&ct=video%2Fmp4');

      expect(
        restore(routePath),
        '/view/$dataTxId?n=talk.mp4&ct=video%2Fmp4',
      );
    });

    test('a drive link keeps its key out of the half a server is sent',
        () async {
      // Drive links are untouched this cycle, under either strategy (plan
      // §1.1: `/#/drives/{driveId}…`, "Unchanged this cycle"), so the drive
      // key is still an ordinary query parameter.
      final routePath = await parse(
        '/drives/$driveId?name=My%20Drive'
        '&$driveKeyQueryParamName=$validDriveKey',
      );

      final location = restore(routePath);

      expect(
        location,
        parser.restoreRouteInformation(routePath).uri.toString(),
        reason: 'the parser does not branch on the strategy for drive routes',
      );
      expect(location, startsWith('/drives/$driveId?'));
      expect(location, contains(validDriveKey));

      // Which is only safe while drive routes stay hash-rooted. This is the
      // URL the address bar would actually hold on the build that ships...
      final url = '${kAppUrlStrategy.linkPrefix}$location';

      // ...and the half of it the browser sends to the host.
      expect(
        url.split('#').first,
        isNot(contains(validDriveKey)),
        reason: 'a private drive key would reach the server on every page '
            'load and every refresh, and land in its access log. Serving '
            'drive routes on the path strategy has to wait until the key '
            'moves out of the query (plan §1.1 leaves drive links alone this '
            'cycle).',
      );
    });

    test('restores a round trip', () async {
      final routePath = await parse(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: sharedPayload,
          rawFileKey: validFileKey,
          route: SharedFileLinkRoute.share,
          keyPlacement: SharedFileLinkKeyPlacement.fragment,
        ),
      );

      final restored = await pathParser.parseRouteInformation(
        pathParser.restoreRouteInformation(routePath),
      );

      expect(restored.sharedFileId, fileId);
      expect(restored.sharedFileLinkPayload, routePath.sharedFileLinkPayload);
      expect(restored.sharedRawFileKey, validFileKey);
    });
  });

  group('restoreRouteInformation under hash routing', () {
    test('a raw transaction link restores with its hints', () async {
      final routePath = await parse('/view/$dataTxId?n=talk.mp4');

      expect(
        parser.restoreRouteInformation(routePath).uri.toString(),
        '/view/$dataTxId?n=talk.mp4',
      );
    });
  });
}
