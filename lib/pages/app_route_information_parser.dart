import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import 'pages.dart';

const fileKeyQueryParamName = 'fileKey';
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
          final fileKeyBase64 = uri.queryParameters[fileKeyQueryParamName];

          if (fileKeyBase64 != null && fileKeyBase64.isNotEmpty) {
            try {
              final sharedFilePkBytes =
                  utils.decodeBase64ToBytes(fileKeyBase64);

              return AppRoutePath.sharedFile(
                sharedFileId: fileId,
                sharedFilePk: SecretKey(sharedFilePkBytes),
                sharedRawFileKey: fileKeyBase64,
              );
            } catch (e) {
              // The key in the link is damaged - links get truncated and
              // mangled in transit all the time. Drop it and let the page load
              // without a key so the file can still be unlocked by hand,
              // instead of throwing while parsing the route. The flag carries
              // the reason through to the page, which tells the recipient the
              // link is damaged rather than silently asking for a key.
              logger.e(
                'Failed to decode the file key in the shared file link',
                e,
              );

              return AppRoutePath.sharedFile(
                sharedFileId: fileId,
                sharedFileKeyIsDamaged: true,
              );
            }
          } else {
            return AppRoutePath.sharedFile(sharedFileId: fileId);
          }
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
      final sharedFilePath = '/file/${configuration.sharedFileId}/view';

      if (configuration.sharedRawFileKey != null) {
        return RouteInformation(
          uri: Uri.parse(
              '$sharedFilePath?$fileKeyQueryParamName=${configuration.sharedRawFileKey}'),
        );
      } else {
        return RouteInformation(uri: Uri.parse(sharedFilePath));
      }
    }

    return RouteInformation(uri: Uri.parse('/'));
  }
}
