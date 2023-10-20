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
    final uri = Uri.parse(routeInformation.location!);
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
          if (driveKeyBase64 != null) {
            final sharedDrivePkBytes =
                utils.decodeBase64ToBytes(driveKeyBase64);
            return AppRoutePath.driveDetail(
              driveId: driveId,
              driveName: name,
              sharedDrivePk: SecretKey(sharedDrivePkBytes),
              sharedRawDriveKey: driveKeyBase64,
            );
          } else if (uri.pathSegments.length == 2) {
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
  RouteInformation restoreRouteInformation(AppRoutePath configuration) {
    if (configuration.signingIn) {
      return const RouteInformation(location: '/sign-in');
    } else if (configuration.getStarted) {
      return const RouteInformation(location: '/get-started');
    } else if (configuration.driveId != null) {
      if (configuration.driveName != null &&
          configuration.sharedRawDriveKey != null) {
        return RouteInformation(
          location:
              '/drives/${configuration.driveId}?name=${configuration.driveName}'
              '&$driveKeyQueryParamName=${configuration.sharedRawDriveKey}',
        );
      }

      return configuration.driveFolderId == null
          ? RouteInformation(location: '/drives/${configuration.driveId}')
          : RouteInformation(
              location:
                  '/drives/${configuration.driveId}/folders/${configuration.driveFolderId}',
            );
    } else if (configuration.sharedFileId != null) {
      final sharedFilePath = '/file/${configuration.sharedFileId}/view';

      if (configuration.sharedRawFileKey != null) {
        return RouteInformation(
          location:
              '$sharedFilePath?$fileKeyQueryParamName=${configuration.sharedRawFileKey}',
        );
      } else {
        return RouteInformation(location: sharedFilePath);
      }
    }

    return const RouteInformation(location: '/');
  }
}
