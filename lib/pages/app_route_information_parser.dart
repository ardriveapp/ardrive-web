import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/utils/app_url_strategy.dart';
import 'package:ardrive/utils/legacy_share_link.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/raw_transaction_link.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive/utils/validate_arweave_id.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import 'pages.dart';

/// The v1 file key parameter. Honored forever - see
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.1.
const fileKeyQueryParamName = SharedFileLinkParams.legacyKey;
const driveKeyQueryParamName = 'driveKey';

/// Why something failed, with nothing of what it failed on.
///
/// A [FormatException] carries the string it could not parse and prints a
/// window of it from `toString()`. When that string is a key - or a link that
/// contains one - the exception object must never reach the log, which is held
/// in memory and can be exported by email from the sidebar. Only the reason
/// travels, which is all a log of this can usefully say anyway.
String _reasonWithoutValue(Object error) =>
    error is FormatException ? error.message : '${error.runtimeType}';

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  AppRouteInformationParser({this.urlStrategy = kAppUrlStrategy});

  /// The strategy the app is served on.
  ///
  /// Parsing does not depend on it - every route shape parses under both, and
  /// legacy links resolve forever either way. Only [restoreRouteInformation]
  /// does: it decides which shape the address bar is written back in.
  final AppUrlStrategy urlStrategy;

  @override
  Future<AppRoutePath> parseRouteInformation(
      RouteInformation routeInformation) async {
    // A malformed URI, or a bad percent-escape anywhere in the query, throws
    // out of `Uri.parse`/`queryParameters` before any per-route handling runs —
    // the same crash class as an undecodable key, one layer earlier. Degrade to
    // the unknown route instead of letting route parsing throw.
    final Uri uri;
    try {
      // Under path routing the host only ever saw `/` and the whole legacy
      // route arrives inside the fragment; this hands back the route it names
      // and is a no-op for every location the hash strategy produces (§4.1).
      // TODO: Remove deprecated member use
      // ignore: deprecated_member_use
      uri = Uri.parse(normalizeHashRouteLocation(routeInformation.location));
      // Touch the query here so a bad escape surfaces inside this guard rather
      // than at an unguarded `uri.queryParameters` access further down.
      uri.queryParameters;
    } on FormatException catch (e) {
      // The reason, never the exception object: `FormatException.toString()`
      // prints a window of its `source`, and the source here is the location -
      // which on a key-bearing link is the key. Same rule as
      // `SharedFileLinkKey.parse` (`lib/utils/shared_file_link.dart`, rule 3).
      logger.e('Failed to parse the route URI: ${e.message}');
      return AppRoutePath.unknown();
    }
    // Handle '/'
    if (uri.pathSegments.isEmpty) {
      return AppRoutePath.unknown();
    }

    switch (uri.pathSegments.first) {
      case 'sign-in':
        // Handle '/sign-in'
        return AppRoutePath.signIn();
      case 'get-started':
        return AppRoutePath.getStarted();
      case 'drives':
        // Handle '/drives' - the list of the user's drives. Only the bare
        // segment: every longer shape below addresses a particular drive and
        // is a link that may already be in the wild.
        if (uri.pathSegments.length == 1) {
          return AppRoutePath.drivesList();
        }

        if (uri.pathSegments.length > 1) {
          final driveId = uri.pathSegments[1];
          final name = uri.queryParameters['name'];
          final driveKeyBase64 = uri.queryParameters[driveKeyQueryParamName];

          DriveKey? sharedDriveKey;
          String? sharedRawDriveKey;

          // Decoded once, before the route shape is decided, so that the key
          // reaches whichever route matches. This used to sit inside the drive
          // branch and return from there, which meant a *valid* key made the
          // folder segments unreachable: `/drives/{id}/folders/{fid}?driveKey=`
          // silently resolved to the drive root and lost the folder. Only a
          // damaged key ever reached the folder route, which is the wrong way
          // round.
          if (driveKeyBase64 != null && driveKeyBase64.isNotEmpty) {
            try {
              sharedDriveKey = DriveKey(
                SecretKey(utils.decodeBase64ToBytes(driveKeyBase64)),
                true,
              );
              sharedRawDriveKey = driveKeyBase64;
            } catch (e) {
              // A damaged key must not throw while the route is being parsed.
              // Drop it and carry on to the keyless route.
              //
              // The reason is logged and never the exception object: the
              // `source` of the `FormatException` a base64 decoder throws *is*
              // the drive key, and `toString()` prints a window of it into a
              // log the user can export by email.
              logger.e(
                'Failed to decode the drive key in the shared drive link: '
                '${_reasonWithoutValue(e)}',
              );
            }
          }

          if (uri.pathSegments.length == 2) {
            // Handle '/drives/:driveId'
            return AppRoutePath.driveDetail(
              driveId: driveId,
              driveName: name,
              sharedDrivePk: sharedDriveKey,
              sharedRawDriveKey: sharedRawDriveKey,
            );
          } else if (uri.pathSegments.length == 4 &&
              uri.pathSegments[2] == 'folders') {
            //  Handle /drives/:driveId/folders/:folderId
            return AppRoutePath.folderDetail(
              driveId: driveId,
              driveFolderId: uri.pathSegments[3],
              driveName: name,
              sharedDrivePk: sharedDriveKey,
              sharedRawDriveKey: sharedRawDriveKey,
            );
          }
        }

        return AppRoutePath.unknown();
      case SharedFileLinkRoute.legacySegment:
        // Handle '/file/:sharedFileId/view' - the legacy shared file route,
        // honored forever and under either URL strategy (§4.1).
        if (uri.pathSegments.length == 3 &&
            uri.pathSegments[2] == SharedFileLinkRoute.legacyViewSegment) {
          return _sharedFileRoute(uri, uri.pathSegments[1]);
        }

        return AppRoutePath.unknown();
      case SharedFileLinkRoute.shareSegment:
        // Handle '/share/:sharedFileId' - the canonical route of §1.1. Parsed
        // under either strategy; only reachable as a *path* once the host
        // answers it with `index.html`.
        if (uri.pathSegments.length == 2) {
          return _sharedFileRoute(uri, uri.pathSegments[1]);
        }

        return AppRoutePath.unknown();
      case rawTransactionRouteSegment:
        // Handle '/view/:txId' - the generalized viewer of §1.3.
        if (uri.pathSegments.length == 2) {
          final txId = uri.pathSegments[1];

          // The id is the whole route: an id that is not an id addresses
          // nothing, so there is no page to show and nothing to degrade to.
          if (!isArweaveTransactionID(txId)) {
            logger.w(
              'Ignoring a raw transaction link: the id is not a 43 character '
              'base64url transaction id.',
            );

            return AppRoutePath.unknown();
          }

          // Hints only, and dropped one by one when malformed - the viewer
          // resolves the truth from the gateway either way. Same fields, same
          // validation as the shared file schema's `n`/`ct`.
          return AppRoutePath.rawTransaction(
            txId: txId,
            name: SharedFileLinkPayload.sanitizeName(
              uri.queryParameters[SharedFileLinkParams.name],
            ),
            contentType: SharedFileLinkPayload.sanitizeContentType(
              uri.queryParameters[SharedFileLinkParams.contentType],
            ),
          );
        }

        return AppRoutePath.unknown();
      default:
        return AppRoutePath.unknown();
    }
  }

  /// The shared file route, from either of the two shapes that address it.
  AppRoutePath _sharedFileRoute(Uri uri, String fileId) {
    // One resolution for every key source and both link schemas: the `#k=`
    // fragment, the v2 `k` parameter, and the v1 `fileKey` parameter, in that
    // order of precedence (§4.2).
    //
    // A key that is present but cannot be used is dropped rather than thrown -
    // links get truncated and mangled in transit all the time - and the damaged
    // flag carries the reason through to the page, which tells the recipient
    // the link is damaged rather than silently asking for a key.
    final fileKey = SharedFileLinkKey.resolve(uri);

    // `null` for a v1 link, which resolves over GraphQL as it always has.
    // Malformed v2 fields are dropped field by field, never fatally.
    final payload = SharedFileLinkPayload.tryParse(uri, key: fileKey);

    return AppRoutePath.sharedFile(
      sharedFileId: fileId,
      sharedFilePk: fileKey.secretKey,
      sharedRawFileKey: fileKey.raw,
      sharedFileKeyIsDamaged: fileKey.isDamaged,
      linkPayload: payload,
    );
  }

  @override
  RouteInformation restoreRouteInformation(AppRoutePath configuration) {
    if (configuration.signingIn) {
      return RouteInformation(
        uri: Uri.parse('/sign-in'),
      );
    } else if (configuration.getStarted) {
      return RouteInformation(
        uri: Uri.parse('/get-started'),
      );
    } else if (configuration.drivesList) {
      // Checked before [driveId]: a drive stays selected underneath the list -
      // the sidebar has to show something - so the two are set at once and
      // this is what says which one the user is looking at.
      return RouteInformation(
        uri: Uri.parse('/drives'),
      );
    } else if (configuration.driveId != null) {
      final path = configuration.driveFolderId == null
          ? '/drives/${configuration.driveId}'
          : '/drives/${configuration.driveId}'
              '/folders/${configuration.driveFolderId}';

      // Each part is written when it is there, rather than only when both are.
      // A private drive link no longer carries a name, and the old shape wrote
      // the key back *only* alongside one - so the key silently fell out of the
      // address bar and a refresh asked the recipient for a key their link
      // already had.
      final query = <String>[
        if (configuration.driveName != null)
          'name=${Uri.encodeQueryComponent(configuration.driveName!)}',
        if (configuration.sharedRawDriveKey != null)
          '$driveKeyQueryParamName=${configuration.sharedRawDriveKey}',
      ];

      return RouteInformation(
        uri: Uri.parse(query.isEmpty ? path : '$path?${query.join('&')}'),
      );
    } else if (configuration.rawTransactionId != null) {
      return RouteInformation(
        uri: Uri.parse(
          buildRawTransactionViewLocation(
            txId: configuration.rawTransactionId!,
            name: configuration.rawTransactionName,
            contentType: configuration.rawTransactionContentType,
          ),
        ),
      );
    } else if (configuration.sharedFileId != null) {
      // On the hash route everything this returns lands after the `#`, so the
      // key never reaches a server wherever it sits. On a path route the query
      // *is* sent, so the key moves to the fragment - which is exactly what
      // [AppUrlStrategy.fileKeyPlacement] says, and why this is one argument
      // rather than a rewrite.
      return RouteInformation(
        uri: Uri.parse(
          buildSharedFileLinkLocation(
            fileId: configuration.sharedFileId!,
            payload: configuration.sharedFileLinkPayload,
            rawFileKey: configuration.sharedRawFileKey,
            route: urlStrategy.sharedFileRoute,
            keyPlacement: urlStrategy.fileKeyPlacement,
          ),
        ),
      );
    }

    return RouteInformation(uri: Uri.parse('/'));
  }
}
