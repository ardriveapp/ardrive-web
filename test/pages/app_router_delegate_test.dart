import 'package:ardrive/pages/app_route_information_parser.dart';
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

    test('never carries another drive\'s folder in under its name', () async {
      // The pending marker used to preserve whatever folder was in view when
      // its drive arrived, rather than restoring the one the link named. A
      // recipient who wandered off before the drive was selected therefore
      // landed on drive A showing a folder that belongs to drive B.
      const otherFolderId = 'd5eaed3d-6e5d-7f4e-bd5f-9f4d3e6f7a81';

      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );

      // Away to another drive, and into a folder there.
      delegate.onDriveSelected(otherDriveId);
      delegate.driveFolderId = otherFolderId;

      // Now the linked drive finally arrives.
      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, folderId);
      expect(delegate.driveFolderId, isNot(otherFolderId));
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

  group('the way back to the drives list', () {
    // `showingDrivesList` was set in exactly one place - on login - so once a
    // drive was opened the list was unreachable without the browser's back
    // button or typing the address.
    final parser = AppRouteInformationParser();

    String addressBar(AppRouterDelegate delegate) =>
        parser.restoreRouteInformation(delegate.currentConfiguration).uri.path;

    test('lands where a login lands, and says so in the address bar', () async {
      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );
      delegate.onDriveSelected(driveId);

      delegate.showDrivesList();

      // The same single flag the login path sets - and it is the flag, not
      // `driveId == null`, that decides which of the two is on screen.
      expect(delegate.showingDrivesList, isTrue);
      expect(delegate.currentConfiguration.drivesList, isTrue);
      // Bookmarkable, and the browser's own back and forward agree with it.
      expect(addressBar(delegate), '/drives');
    });

    test('leaves the drive selected underneath, folder and all', () async {
      // Going back into the drive is one tap, and it lands where the user was
      // rather than at the drive's root.
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );
      delegate.onDriveSelected(driveId);

      delegate.showDrivesList();

      expect(delegate.driveId, driveId);
      expect(delegate.driveFolderId, folderId);
    });

    test('tells the router every time it is asked', () async {
      // No early return. There is no condition this method can test that
      // proves the list is on screen, and every version of that guess ended
      // with Home dead for the rest of the session: the flag read true, the
      // request was dropped in silence, and the address bar insisted
      // `/drives` over a drive. One repeated history entry is the cheaper
      // failure by a wide margin.
      var notifications = 0;
      delegate.addListener(() => notifications++);

      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );

      delegate.showDrivesList();
      expect(notifications, 1, reason: 'the router has to be told');

      delegate.showDrivesList();
      expect(notifications, 2,
          reason: 'a second tap must not be swallowed on the strength of a '
              'flag that is not proof of what is on screen');

      expect(delegate.showingDrivesList, isTrue);
      expect(delegate.currentConfiguration.drivesList, isTrue);
    });

    test('and clears every route that outranks the list', () async {
      // All of these are checked before the drives list in `build`, so any one
      // of them left set would render something else while the flag says
      // otherwise - which is the state Home could never get out of.
      await delegate.setNewRoutePath(
        AppRoutePath.driveDetail(driveId: driveId),
      );
      delegate.signingIn = true;
      delegate.gettingStarted = true;

      delegate.showDrivesList();

      expect(delegate.signingIn, isFalse);
      expect(delegate.gettingStarted, isFalse);
      expect(delegate.isViewingSharedFile, isFalse);
      expect(delegate.isViewingRawTransaction, isFalse);
      expect(delegate.showingDrivesList, isTrue);
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

  /// The drives list can ask for a drive's info panel but cannot open it: the
  /// panel is `DriveDetailCubit.selectDataItem`, and the cubit that page
  /// provides is built against no drive and is a different instance from the
  /// explorer's. The request travels the way a folder deep link's does.
  group('the info a drives list asked for', () {
    test('survives the drive being opened', () async {
      delegate.requestDriveInfo(driveId);
      delegate.openDriveFromList(driveId);

      expect(delegate.pendingInfoDriveId, driveId,
          reason: 'opening the drive is how the request gets somewhere to be '
              'honoured; it must not clear it on the way');
    });

    test('is not standing when nobody asked', () async {
      delegate.openDriveFromList(driveId);

      expect(delegate.pendingInfoDriveId, isNull);
    });

    test('is dropped on logout, like every other pending intent', () async {
      delegate.requestDriveInfo(driveId);

      delegate.clearState();

      expect(delegate.pendingInfoDriveId, isNull,
          reason: "the next session must not inherit the last one's request");
    });

    test('is replaced, not stacked, when a second drive is asked about',
        () async {
      delegate.requestDriveInfo(driveId);
      delegate.requestDriveInfo('drive-2');

      expect(delegate.pendingInfoDriveId, 'drive-2');
    });
  });
}
