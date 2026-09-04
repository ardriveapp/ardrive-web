import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The one thing the drives list is not allowed to break.
///
/// `/drives/{id}`, `/drives/{id}/folders/{id}` and the shared file routes are
/// permanent public API - links already in the wild have to keep resolving,
/// and they have to resolve to the drive, not to a list with the drive
/// somewhere in it. A landing page that swallowed them would be a silent
/// regression for every link ever sent.
void main() {
  const driveId = '00000000-0000-0000-0000-000000000002';
  const folderId = '00000000-0000-0000-0000-000000000003';
  const fileId = '00000000-0000-0000-0000-000000000001';

  final parser = AppRouteInformationParser();

  Future<AppRoutePath> parse(String location) => parser.parseRouteInformation(
        RouteInformation(uri: Uri.parse(location)),
      );

  group('deep links bypass the list entirely', () {
    test('a drive link still opens its drive', () async {
      final route = await parse('/drives/$driveId');

      expect(route.driveId, driveId);
      expect(route.drivesList, isFalse);
    });

    test('a folder link still opens its folder', () async {
      final route = await parse('/drives/$driveId/folders/$folderId');

      expect(route.driveId, driveId);
      expect(route.driveFolderId, folderId);
      expect(route.drivesList, isFalse);
    });

    test('a drive link with a name and a key is untouched', () async {
      final route = await parse('/drives/$driveId?name=Photos');

      expect(route.driveId, driveId);
      expect(route.driveName, 'Photos');
      expect(route.drivesList, isFalse);
    });

    test('a shared file link still opens the file', () async {
      final route = await parse('/file/$fileId/view');

      expect(route.sharedFileId, fileId);
      expect(route.drivesList, isFalse);
    });
  });

  group('the list has a route of its own', () {
    test('/drives is the list', () async {
      final route = await parse('/drives');

      expect(route.drivesList, isTrue);
      expect(route.driveId, isNull);
    });

    test('and is written back as /drives', () {
      final information = parser.restoreRouteInformation(
        AppRoutePath.drivesList(),
      );

      expect(information.uri.toString(), '/drives');
    });

    test('a drive link is still written back as the drive it names', () {
      final information = parser.restoreRouteInformation(
        AppRoutePath.driveDetail(driveId: driveId),
      );

      expect(information.uri.toString(), '/drives/$driveId');
    });
  });

  group('what a login lands on', () {
    late AppRouterDelegate delegate;

    setUp(() => delegate = AppRouterDelegate());

    test('nothing to honour, so the list', () async {
      await delegate.setNewRoutePath(AppRoutePath.unknown());

      expect(delegate.hasARouteToHonour, isFalse);
    });

    test('a drive link is honoured instead', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );

      expect(delegate.hasARouteToHonour, isTrue);
      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.driveId, driveId);
    });

    test('a folder link is honoured instead', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      expect(delegate.hasARouteToHonour, isTrue);
      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.driveFolderId, folderId);
    });

    test('a shared file link is honoured instead', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.sharedFile(sharedFileId: fileId),
      );

      expect(delegate.hasARouteToHonour, isTrue);
      expect(delegate.showingDrivesList, isFalse);
    });

    test('/drives shows the list and selects no drive', () async {
      await delegate.setNewRoutePath(AppRoutePath.drivesList());

      expect(delegate.showingDrivesList, isTrue);
      expect(delegate.driveId, isNull);
      expect(delegate.currentConfiguration.drivesList, isTrue);
    });
  });

  group('opening a drive from the list', () {
    late AppRouterDelegate delegate;

    setUp(() => delegate = AppRouterDelegate());

    test('leaves the list for that drive', () async {
      await delegate.setNewRoutePath(AppRoutePath.drivesList());

      delegate.openDriveFromList(driveId);

      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.driveId, driveId);
      expect(delegate.currentConfiguration.drivesList, isFalse);
      expect(delegate.currentConfiguration.driveId, driveId);
    });

    test('opens it at its root rather than at whatever folder was last seen',
        () async {
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      delegate.openDriveFromList(driveId);

      expect(delegate.driveFolderId, isNull);
    });
  });

  group('logging out', () {
    test('drops the list along with everything else', () async {
      final delegate = AppRouterDelegate();
      await delegate.setNewRoutePath(AppRoutePath.drivesList());

      delegate.clearState();

      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.signingIn, isTrue);
    });
  });
}
