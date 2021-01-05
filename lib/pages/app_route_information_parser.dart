import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';

import 'pages.dart';

const fileKeyQueryParamName = 'fileKey';

class AppRouteInformationParser extends RouteInformationParser<AppRoutePath> {
  @override
  Future<AppRoutePath> parseRouteInformation(
      RouteInformation routeInformation) async {
    final uri = Uri.parse(routeInformation.location);
    // Handle '/'
    if (uri.pathSegments.isEmpty) {
      return AppRoutePath.unknown();
    }

    switch (uri.pathSegments.first) {
      case 'sign-in':
        return AppRoutePath.signIn();
      case 'drives':
        if (uri.pathSegments.length > 1) {
          final driveId = uri.pathSegments[1];

          if (uri.pathSegments.length == 2) {
            // Handle '/drives/:driveId'
            return AppRoutePath.driveDetail(driveId: driveId);
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

          if (fileKeyBase64 != null) {
            final sharedFilePkBytes = utils.decodeBase64ToBytes(fileKeyBase64);

            return AppRoutePath.sharedFile(
              sharedFileId: fileId,
              sharedFilePk: SecretKey(sharedFilePkBytes),
              sharedRawFileKey: fileKeyBase64,
            );
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
  RouteInformation restoreRouteInformation(AppRoutePath path) {
    if (path.signingIn) {
      return RouteInformation(location: '/sign-in');
    } else if (path.driveId != null) {
      return path.driveFolderId == null
          ? RouteInformation(location: '/drives/${path.driveId}')
          : RouteInformation(
              location: '/drives/${path.driveId}/folders/${path.driveFolderId}',
            );
    } else if (path.sharedFileId != null) {
      final sharedFilePath = '/file/${path.sharedFileId}/view';

      if (path.sharedRawFileKey != null) {
        return RouteInformation(
          location: sharedFilePath +
              '?$fileKeyQueryParamName=${path.sharedRawFileKey}',
        );
      } else {
        return RouteInformation(location: sharedFilePath);
      }
    }

    return RouteInformation(location: '/');
  }
}
