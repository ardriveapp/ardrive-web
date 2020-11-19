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

    // Handle '/drives/:driveId' and '/drives/:driveId/folders/:folderId
    if (uri.pathSegments.length == 2 || uri.pathSegments.length == 4) {
      if (uri.pathSegments[0] != 'drives') return AppRoutePath.unknown();
      final driveId = uri.pathSegments[1];
      if (uri.pathSegments.length == 2) {
        return AppRoutePath(driveId: driveId);
      } else {
        if (uri.pathSegments[2] != 'folders') return AppRoutePath.unknown();
        return AppRoutePath(
            driveId: driveId, driveFolderId: uri.pathSegments[3]);
      }
    }

    // Handle unknown routes
    return AppRoutePath.unknown();
  }

  @override
  RouteInformation restoreRouteInformation(AppRoutePath path) {
    if (path.driveId == null) {
      return RouteInformation(location: '/');
    }
    if (path.driveId != null) {
      if (path.driveFolderId != null) {
        return RouteInformation(
            location: '/drives/${path.driveId}/folders/${path.driveFolderId}');
      } else {
        return RouteInformation(location: '/drives/${path.driveId}');
      }
    }

    return null;
  }
}
