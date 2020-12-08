import 'package:flutter/material.dart';

import 'pages.dart';

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
        // Handle '/file/:sharedFileId'
        if (uri.pathSegments.length > 1) {
          final fileId = uri.pathSegments[1];
          return AppRoutePath.sharedFile(sharedFileId: fileId);
        }

        return AppRoutePath.unknown();
      default:
        return AppRoutePath.unknown();
    }
  }

  @override
  RouteInformation restoreRouteInformation(AppRoutePath path) {
    if (path.driveId != null) {
      return path.driveFolderId == null
          ? RouteInformation(location: '/drives/${path.driveId}')
          : RouteInformation(
              location:
                  '/drives/${path.driveId}/folders/${path.driveFolderId}');
    } else if (path.sharedFileId != null) {
      return RouteInformation(location: '/file/${path.sharedFileId}');
    }

    return RouteInformation(location: '/');
  }
}
