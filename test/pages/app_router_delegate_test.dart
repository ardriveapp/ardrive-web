import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:flutter_test/flutter_test.dart';

/// How a folder link survives the drive being attached under it.
///
/// A folder link only ever opened the folder for someone who already had the
/// drive. Everyone else - which is every stranger a public folder link is sent
/// to - went through the attach flow, which ends by clearing the drive id so
/// the prompt cannot re-fire. The drive was then selected fresh, the folder
/// read as belonging to a different drive, and it was dropped. A folder link
/// was a drive link with extra characters.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';
  const otherDriveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  const folderId = 'c4d9dc2c-5d4c-6e3d-ac4f-8f3c2d5e6f70';

  late AppRouterDelegate delegate;

  setUp(() => delegate = AppRouterDelegate());

  /// What the attach flow does when it finishes: the drive id is cleared so the
  /// attach prompt cannot fire again, and the drive is then selected fresh.
  void attachCompletes() => delegate.driveId = null;

  group('a folder link', () {
    test('opens its folder once the drive it names is selected', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      attachCompletes();
      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, folderId);
      expect(delegate.driveId, driveId);
    });

    test('opens its folder for someone who already had the drive', () async {
      // No attach in between: the drive is already selected.
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, folderId);
    });

    test('is released after it has been honored', () async {
      // Otherwise every later visit to that drive would jump back into the
      // folder the link named, long after the link was opened.
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      attachCompletes();
      delegate.onDriveSelected(driveId);

      // Away to another drive, and back.
      delegate.onDriveSelected(otherDriveId);
      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, isNull);
    });

    test('does not follow the user to a different drive', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      delegate.onDriveSelected(otherDriveId);

      expect(delegate.driveFolderId, isNull);
      expect(delegate.driveId, otherDriveId);
    });
  });

  group('a drive link', () {
    test('holds nothing back, since it names no folder', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );

      // The folder in view at the time belongs to wherever the user was.
      delegate.driveFolderId = folderId;

      attachCompletes();
      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, isNull);
    });
  });

  group('ordinary navigation', () {
    test('still discards the folder when the drive changes', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );

      delegate.onDriveSelected(driveId);
      delegate.driveFolderId = folderId;

      delegate.onDriveSelected(otherDriveId);

      expect(delegate.driveFolderId, isNull);
    });

    test('keeps the folder while the drive stays the same', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );

      delegate.onDriveSelected(driveId);
      delegate.driveFolderId = folderId;

      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, folderId);
    });
  });
}
