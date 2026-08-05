import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import 'pages.dart';

/// The v1 file key parameter. Honored forever - see
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.1.
const fileKeyQueryParamName = SharedFileLinkParams.legacyKey;
const driveKeyQueryParamName = 'driveKey';

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(
      RouteInformation routeInformation) async {
    // A malformed URI, or a bad percent-escape anywhere in the query, throws
    // out of `Uri.parse`/`queryParameters` before any per-route handling runs —
    // the same crash class as an undecodable key, one layer earlier. Degrade to
    // the unknown route instead of letting route parsing throw.
    final Uri uri;
    try {
      // TODO: Remove deprecated member use
      // ignore: deprecated_member_use
      uri = Uri.parse(routeInformation.location);
      // Touch the query here so a bad escape surfaces inside this guard rather
      // than at an unguarded `uri.queryParameters` access further down.
      uri.queryParameters;
    } on FormatException catch (e) {
      logger.e('Failed to parse the route URI', e);
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
        if (uri.pathSegments.length > 1) {
          final driveId = uri.pathSegments[1];
          final name = uri.queryParameters['name'];
          final driveKeyBase64 = uri.queryParameters[driveKeyQueryParamName];
          if (driveKeyBase64 != null && driveKeyBase64.isNotEmpty) {
            try {
              final sharedDrivePkBytes =
                  utils.decodeBase64ToBytes(driveKeyBase64);

              return AppRoutePath.driveDetail(
                driveId: driveId,
                driveName: name,
                sharedDrivePk: DriveKey(SecretKey(sharedDrivePkBytes), true),
                sharedRawDriveKey: driveKeyBase64,
              );
            } catch (e) {
              // Same as the shared file link below: a damaged key must not
              // throw while the route is being parsed. Drop it and carry on to
              // the keyless drive route.
              logger.e(
                'Failed to decode the drive key in the shared drive link',
                e,
              );
            }
          }

          if (uri.pathSegments.length == 2) {
            // Handle '/drives/:driveId'
            return AppRoutePath.driveDetail(driveId: driveId, driveName: name);
          } else if (uri.pathSegments.length == 4 &&
              uri.pathSegments[2] == 'folders') {
            //  Handle /drives/:driveId/folders/:folderId
            return AppRoutePath.folderDetail(
                driveId: driveId, driveFolderId: uri.pathSegments[3]);
          }
        }

        return AppRoutePath.unknown();
      case 'file':
        // Handle '/file/:sharedFileId/view'
        if (uri.pathSegments.length == 3 && uri.pathSegments[2] == 'view') {
          final fileId = uri.pathSegments[1];

          // One resolution for every key source and both link schemas: the
          // `#k=` fragment, the v2 `k` parameter, and the v1 `fileKey`
          // parameter, in that order of precedence (§4.2).
          //
          // A key that is present but cannot be used is dropped rather than
          // thrown - links get truncated and mangled in transit all the time -
          // and the damaged flag carries the reason through to the page, which
          // tells the recipient the link is damaged rather than silently
          // asking for a key.
          final fileKey = SharedFileLinkKey.resolve(uri);

          // `null` for a v1 link, which resolves over GraphQL as it always
          // has. Malformed v2 fields are dropped field by field, never fatally.
          final payload = SharedFileLinkPayload.tryParse(uri, key: fileKey);

          return AppRoutePath.sharedFile(
            sharedFileId: fileId,
            sharedFilePk: fileKey.secretKey,
            sharedRawFileKey: fileKey.raw,
            sharedFileKeyIsDamaged: fileKey.isDamaged,
            linkPayload: payload,
          );
        }

        return AppRoutePath.unknown();
      default:
        return AppRoutePath.unknown();
    }
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
    } else if (configuration.driveId != null) {
      if (configuration.driveName != null &&
          configuration.sharedRawDriveKey != null) {
        return RouteInformation(
          uri: Uri.parse(
              '/drives/${configuration.driveId}?name=${configuration.driveName}'
              '&$driveKeyQueryParamName=${configuration.sharedRawDriveKey}'),
        );
      }

      return configuration.driveFolderId == null
          ? RouteInformation(uri: Uri.parse('/drives/${configuration.driveId}'))
          : RouteInformation(
              uri: Uri.parse(
                  '/drives/${configuration.driveId}/folders/${configuration.driveFolderId}'),
            );
    } else if (configuration.sharedFileId != null) {
      // Everything this returns lands after the `#` of the hash route, so the
      // key never reaches a server. When the app moves to path routing the key
      // has to move to the fragment - `buildSharedFileLinkLocation` takes that
      // as a parameter so the switch is one argument, not a rewrite.
      return RouteInformation(
        uri: Uri.parse(
          buildSharedFileLinkLocation(
            fileId: configuration.sharedFileId!,
            payload: configuration.sharedFileLinkPayload,
            rawFileKey: configuration.sharedRawFileKey,
          ),
        ),
      );
    }

    return RouteInformation(uri: Uri.parse('/'));
  }
}
