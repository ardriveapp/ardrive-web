import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_route_information_parser.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:ardrive/upload_entry/domain/upload_request.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

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

  // A waiting upload holds a timer; logging out is what drops it.
  tearDown(() => delegate.clearState());

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

  group('the attach prompt a drive link opened', () {
    // A link to a drive the app does not have opens the attach prompt.
    // Cancelling it used to clear the drive and leave nothing to show: a blank
    // page for a visitor, and an explorer with no drive for a signed-in user.
    final parser = AppRouteInformationParser();

    String addressBar(AppRouterDelegate delegate) =>
        parser.restoreRouteInformation(delegate.currentConfiguration).uri.path;

    Future<void> openLink({String? folder}) => delegate.setNewRoutePath(
          folder == null
              ? AppRoutePath.driveDetail(driveId: driveId, driveName: 'Shared')
              : AppRoutePath.folderDetail(
                  driveId: driveId,
                  driveFolderId: folder,
                ),
        );

    test('cancelled by a signed-in user lands on the drives list', () async {
      await openLink(folder: folderId);
      var notifications = 0;
      delegate.addListener(() => notifications++);

      delegate.landAfterAttachPrompt(attached: false, loggedIn: true);

      expect(delegate.showingDrivesList, isTrue);
      expect(delegate.signingIn, isFalse);
      expect(delegate.driveId, isNull);
      expect(delegate.driveName, isNull);
      expect(delegate.driveFolderId, isNull);
      expect(addressBar(delegate), '/drives');
      expect(notifications, greaterThan(0));
    });

    test('cancelled by a visitor lands on sign in', () async {
      await openLink();

      delegate.landAfterAttachPrompt(attached: false, loggedIn: false);

      expect(delegate.signingIn, isTrue);
      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.driveId, isNull);
      expect(delegate.tryingToViewDrive, isFalse);
      expect(addressBar(delegate), '/sign-in');
      // Nothing left for signing in to honour, so they land on Your drives
      // afterwards rather than back in the dialog.
      expect(delegate.hasARouteToHonour, isFalse);
      expect(delegate.pendingInfoDriveId, isNull);
    });

    test('drops the key the link carried when it is cancelled', () async {
      await openLink();
      delegate.sharedRawDriveKey = 'raw-key';

      delegate.landAfterAttachPrompt(attached: false, loggedIn: false);

      expect(delegate.sharedRawDriveKey, isNull);
      expect(delegate.tryingToViewSharedPrivateDrive, isFalse);
    });

    test('a successful attach keeps the drive in view', () async {
      await openLink(folder: folderId);
      var notifications = 0;
      delegate.addListener(() => notifications++);

      for (final loggedIn in [true, false]) {
        delegate.landAfterAttachPrompt(attached: true, loggedIn: loggedIn);

        expect(delegate.driveId, driveId);
        expect(delegate.driveFolderId, folderId);
        expect(delegate.showingDrivesList, isFalse);
        expect(delegate.signingIn, isFalse);
        expect(delegate.tryingToViewDrive, isTrue);
      }
      expect(notifications, 2);
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

  /// A link pasted into a tab that already has the explorer open, or a step
  /// back or forward through its history. The explorer read the route only
  /// when it was built, so these changed the address bar and nothing else.
  group('a link followed in an open tab', () {
    late MockDriveDetailCubit driveDetail;
    late MockDrivesCubit drives;

    setUp(() {
      driveDetail = MockDriveDetailCubit();
      drives = MockDrivesCubit();
      when(() => driveDetail.followLink(
            driveId: any(named: 'driveId'),
            folderId: any(named: 'folderId'),
          )).thenAnswer((_) async {});
      when(() => driveDetail.changeDrive(any())).thenAnswer((_) async {});
      when(() => drives.selectDrive(any())).thenReturn(null);
    });

    void driveSelected(String? selectedDriveId) =>
        when(() => drives.state).thenReturn(DrivesLoadSuccess(
          selectedDriveId: selectedDriveId,
          userDrives: [_drive(driveId), _drive(otherDriveId)],
          sharedDrives: const [],
          drivesWithAlerts: const [],
          canCreateNewDrive: true,
        ));

    const link = RouteLink(driveId: driveId, folderId: folderId);

    test('opens the folder in the drive already on screen', () async {
      driveSelected(driveId);

      delegate.followRouteLink(
        link,
        driveDetail: driveDetail,
        drives: drives,
        explorerIsNew: false,
      );

      verify(() => driveDetail.followLink(driveId: driveId, folderId: folderId))
          .called(1);
      verifyNever(() => drives.selectDrive(any()));
    });

    test('and is not brought back by a later refresh of the drive list',
        () async {
      // The folder held for a link is only let go by a selection of its drive,
      // and none comes when the drive was selected already.
      await delegate.setNewRoutePath(
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
      );
      driveSelected(driveId);

      delegate.followRouteLink(
        link,
        driveDetail: driveDetail,
        drives: drives,
        explorerIsNew: false,
      );

      // The reader moves on, and then the drive list refreshes.
      delegate.driveFolderId = 'another-folder';
      delegate.onDriveSelected(driveId);

      expect(delegate.driveFolderId, 'another-folder');
    });

    test('selects another drive the way the sidebar would', () async {
      driveSelected(otherDriveId);

      delegate.followRouteLink(
        link,
        driveDetail: driveDetail,
        drives: drives,
        explorerIsNew: false,
      );

      verify(() => driveDetail.followLink(driveId: driveId, folderId: folderId))
          .called(1);
      verify(() => drives.selectDrive(driveId)).called(1);
    });

    test('lets an explorer built for the link open it', () async {
      // Pasted on the drives list: the explorer is built from the link, but
      // the sidebar is still on the drive selected before.
      driveSelected(otherDriveId);

      delegate.followRouteLink(
        link,
        driveDetail: driveDetail,
        drives: drives,
        explorerIsNew: true,
      );

      verifyNever(() => driveDetail.followLink(
            driveId: any(named: 'driveId'),
            folderId: any(named: 'folderId'),
          ));
      verify(() => drives.selectDrive(driveId)).called(1);
    });

    test('sends a visitor with no drives to the drive itself', () async {
      // Nothing to select it among: the explorer goes there, and offers to
      // attach it.
      when(() => drives.state)
          .thenReturn(DrivesLoadedWithNoDrivesFound(canCreateNewDrive: false));
      when(() => driveDetail.currentDriveId).thenReturn(otherDriveId);

      delegate.followRouteLink(
        link,
        driveDetail: driveDetail,
        drives: drives,
        explorerIsNew: false,
      );

      verify(() => driveDetail.changeDrive(driveId)).called(1);
      verifyNever(() => drives.selectDrive(any()));
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

  /// An upload pressed away from any drive. It can only start once its drive
  /// is open, so it waits here the way the info request does, and the explorer
  /// takes it when that drive reports in.
  group('the upload somebody asked for', () {
    const request = UploadRequest(driveId: driveId, isFolderUpload: true);

    test('survives the drive being opened', () async {
      delegate.requestUpload(request);
      delegate.openDriveFromList(driveId);

      expect(delegate.pendingUpload, request);
    });

    test('is dropped on logout, like every other pending intent', () async {
      delegate.requestUpload(request);

      delegate.clearState();

      expect(delegate.pendingUpload, isNull);
    });

    /// An upload waits for the second or two a drive takes to open, never for
    /// a sync. Held longer, the dialog would land minutes later on whatever
    /// the reader had moved on to, or on a later visit to that drive.
    testWidgets('expires if its drive does not open in time', (tester) async {
      delegate.requestUpload(request);

      await tester.pump(
        AppRouterDelegate.uploadWaitLimit - const Duration(milliseconds: 1),
      );
      expect(delegate.pendingUpload, request, reason: 'still opening');

      await tester.pump(const Duration(milliseconds: 1));
      expect(delegate.pendingUpload, isNull);
    });

    testWidgets('restarts that clock when pressed again', (tester) async {
      const second =
          UploadRequest(driveId: otherDriveId, isFolderUpload: false);

      delegate.requestUpload(request);
      await tester.pump(const Duration(seconds: 8));
      delegate.requestUpload(second);
      await tester.pump(const Duration(seconds: 8));

      expect(delegate.pendingUpload, second);

      await tester.pump(const Duration(seconds: 2));
      expect(delegate.pendingUpload, isNull);
    });

    test('is replaced, not stacked, by a second press', () async {
      const second =
          UploadRequest(driveId: otherDriveId, isFolderUpload: false);

      delegate.requestUpload(request);
      delegate.requestUpload(second);

      expect(delegate.pendingUpload, second);
    });
  });

  /// A search result opened from the drives list, by the road that actually
  /// runs.
  ///
  /// This is the group that was missing, and its absence shipped a broken
  /// feature. The first version tested `requestFolder` followed by
  /// [AppRouterDelegate.onDriveSelected] - which passes, and proves nothing,
  /// because `onDriveSelected` is only mounted on the explorer's branch of the
  /// router and never sees a drive opened from the list.
  ///
  /// From the list, `OpenDriveOnSelection` hears the selection and calls
  /// [AppRouterDelegate.openDriveFromList] - which cleared the pending folder
  /// outright, so the reader landed at the root of the right drive instead of at
  /// the file they searched for.
  group('a search result opened from the drives list', () {
    const itemId = 'd5eaed3d-6e5d-7f4e-bd50-9a4d3e6f7081';

    test('opens the folder it asked for', () {
      delegate.requestFolder(driveId, folderId, itemId: itemId);
      delegate.openDriveFromList(driveId);

      expect(delegate.driveFolderId, folderId);
      expect(delegate.driveId, driveId);
      expect(delegate.showingDrivesList, isFalse);
    });

    test('and hands the file to highlight to that drive, once', () {
      delegate.requestFolder(driveId, folderId, itemId: itemId);
      delegate.openDriveFromList(driveId);

      expect(delegate.takeSelectedItemForTest(driveId), itemId);
      expect(
        delegate.takeSelectedItemForTest(driveId),
        isNull,
        reason: 'coming back to this drive later must not re-select a file '
            'somebody searched for once',
      );
    });

    /// `_driveDetailCubit` is built twice over - once for the drives list
    /// against the root path, once for the explorer against the chosen drive.
    /// Unkeyed, the list's cubit swallows the selection and the file is never
    /// highlighted.
    test('and not to a cubit built for some other drive', () {
      delegate.requestFolder(driveId, folderId, itemId: itemId);
      delegate.openDriveFromList(driveId);

      expect(delegate.takeSelectedItemForTest(otherDriveId), isNull);
      expect(delegate.takeSelectedItemForTest(driveId), itemId);
    });

    /// A row tap, which is what this method was written for: no folder is in
    /// view and the drive opens at its root.
    test('a plain row tap still opens the drive at its root', () {
      delegate.requestFolder(otherDriveId, folderId, itemId: itemId);
      delegate.openDriveFromList(driveId);

      expect(
        delegate.driveFolderId,
        isNull,
        reason: 'a folder asked for in one drive must not open inside another',
      );
      expect(delegate.takeSelectedItemForTest(driveId), isNull);
    });

    /// Every other pending field is cleared on logout, and these are no
    /// different: a search somebody ran before signing out is not an
    /// instruction to whoever signs in next on the same device.
    test('and does not survive a logout', () {
      delegate.requestFolder(driveId, folderId, itemId: itemId);

      delegate.clearState();
      delegate.openDriveFromList(driveId);

      expect(delegate.driveFolderId, isNull);
      expect(delegate.takeSelectedItemForTest(driveId), isNull);
    });

    /// Honoured, but the explorer never built and the reader went back to the
    /// list. The selection dies with the navigation it belonged to.
    test('and is abandoned by going back to the list', () {
      delegate.requestFolder(driveId, folderId, itemId: itemId);
      delegate.openDriveFromList(driveId);

      delegate.showDrivesList();

      expect(delegate.takeSelectedItemForTest(driveId), isNull);
    });

    /// The other half of abandoning: a request that was never honoured at all,
    /// because the reader went back to the list before it was spent. It must
    /// not jump a later, unrelated row tap into that folder.
    test('and an unspent request does not ambush a later row tap', () {
      delegate.requestFolder(driveId, folderId, itemId: itemId);

      delegate.showDrivesList();
      delegate.openDriveFromList(driveId);

      expect(delegate.driveFolderId, isNull);
      expect(delegate.takeSelectedItemForTest(driveId), isNull);
    });

    test('and a request is spent even when it is not honoured', () {
      delegate.requestFolder(otherDriveId, folderId, itemId: itemId);
      delegate.openDriveFromList(driveId);

      // The stale request must not fire the next time its own drive is opened.
      delegate.openDriveFromList(otherDriveId);

      expect(delegate.driveFolderId, isNull);
    });
  });

  group('a drive opened from the sign-in screen', () {
    // The row is written before the router hears about it, so the explorer
    // finds the drive and no attach prompt opens. The sync is the one thing
    // the dialog cannot start, since the sync cubit lives inside the explorer;
    // the router remembers the drive and starts it as the explorer builds.
    final parser = AppRouteInformationParser();

    String addressBar(AppRouterDelegate delegate) => parser
        .restoreRouteInformation(delegate.currentConfiguration)
        .uri
        .toString();

    test('leaves the sign-in page for the drive, with its sync pending',
        () async {
      await delegate.setNewRoutePath(AppRoutePath.signIn());
      var notifications = 0;
      delegate.addListener(() => notifications++);

      delegate.openDriveAsVisitor(driveId: driveId);

      expect(delegate.signingIn, isFalse);
      expect(delegate.gettingStarted, isFalse);
      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.driveId, driveId);
      expect(delegate.driveFolderId, isNull);
      expect(delegate.syncOnOpenDriveId, driveId);
      expect(delegate.hasARouteToHonour, isTrue);
      expect(addressBar(delegate), '/drives/$driveId');
      expect(notifications, 1);
    });

    test('opens at the folder a link named', () async {
      delegate.openDriveAsVisitor(driveId: driveId, folderId: folderId);

      expect(delegate.driveFolderId, folderId);
      expect(addressBar(delegate), '/drives/$driveId/folders/$folderId');

      // And the folder survives the drive being selected under it, as a
      // folder link's does.
      delegate.onDriveSelected(driveId);
      expect(delegate.driveFolderId, folderId);
    });

    test('never puts a private drive\'s key in the address bar', () {
      // A key typed into the dialog would otherwise sit in the browser's
      // history. The key is in memory already; a reload asks for it.
      final key = DriveKey(SecretKey(List.filled(32, 0)), true);

      delegate.openDriveAsVisitor(driveId: driveId, driveKey: key);

      expect(delegate.sharedDriveKey, key);
      expect(delegate.sharedRawDriveKey, isNull);
      expect(addressBar(delegate), '/drives/$driveId');
    });

    test('drops a link\'s key when another drive is selected', () async {
      const otherDriveId = 'f7acaf5f-8a7f-9b6a-df7a-ba6f5a8b9ca3';
      const rawKey = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      await delegate.setNewRoutePath(
        await parser.parseRouteInformation(
          RouteInformation(uri: Uri.parse('/drives/$driveId?driveKey=$rawKey')),
        ),
      );
      expect(delegate.sharedDriveKey, isNotNull);

      // The linked drive itself keeps it.
      delegate.onDriveSelected(driveId);
      expect(delegate.sharedDriveKey, isNotNull);

      // Another drive must not be offered it, stored with it, or shown with
      // it in the address bar.
      delegate.onDriveSelected(otherDriveId);
      expect(delegate.sharedDriveKey, isNull);
      expect(delegate.sharedRawDriveKey, isNull);
      expect(addressBar(delegate), isNot(contains('driveKey')));
    });

    test('forgets the pending sync when the state is cleared', () {
      delegate.openDriveAsVisitor(driveId: driveId);

      delegate.clearState();

      expect(delegate.syncOnOpenDriveId, isNull);
      expect(delegate.driveId, isNull);
      expect(delegate.signingIn, isTrue);
    });

    test('follows a file link to the shared file page', () async {
      const fileId = 'd5eaed3d-6e5d-7f4e-bd5f-9f4d3e6f7a81';
      await delegate.setNewRoutePath(AppRoutePath.signIn());

      await delegate.openRouteAsVisitor(
        AppRoutePath.sharedFile(sharedFileId: fileId),
      );

      expect(delegate.signingIn, isFalse);
      expect(delegate.isViewingSharedFile, isTrue);
      expect(delegate.sharedFileId, fileId);
    });
  });

  group('signing in while viewing a drive', () {
    // The top bar's "Log in" used to log out, which runs clearState and drops
    // the drive, so the visitor who signed in to keep what they were looking
    // at landed on the drives list without it.
    test('keeps the drive, so the login lands back on it', () {
      delegate.openDriveAsVisitor(driveId: driveId, folderId: folderId);
      var notifications = 0;
      delegate.addListener(() => notifications++);

      delegate.signInKeepingDrive();

      expect(delegate.signingIn, isTrue);
      expect(delegate.gettingStarted, isFalse);
      expect(delegate.showingDrivesList, isFalse);
      expect(delegate.driveId, driveId);
      expect(delegate.driveFolderId, folderId);
      expect(delegate.hasARouteToHonour, isTrue);
      expect(notifications, 1);
    });

    test('keeps a private drive\'s key too', () {
      final key = DriveKey(SecretKey(List.filled(32, 0)), true);
      delegate.openDriveAsVisitor(driveId: driveId, driveKey: key);

      delegate.signInKeepingDrive();

      expect(delegate.sharedDriveKey, key);
    });
  });

  // The page used to stay blank (the HTML splash) until the database had
  // opened and answered whether there was an account, which on a phone was
  // most of the load.
  group('the sign-in page while the check for an account runs', () {
    final checking = ProfileCheckingAvailability();

    tearDown(() => PublicationMode.debugSet(null));

    test('shows for a start with no link, whatever the address', () async {
      for (final path in [
        AppRoutePath.unknown(),
        AppRoutePath.signIn(),
        AppRoutePath.drivesList(),
        AppRoutePath.names(),
        AppRoutePath.webPages(),
      ]) {
        delegate = AppRouterDelegate();
        await delegate.setNewRoutePath(path);
        expect(delegate.signsInWhileChecking(checking), isTrue,
            reason: '$path');
      }
    });

    test('waits for a link, which can end elsewhere for a visitor', () async {
      for (final path in [
        AppRoutePath.driveDetail(driveId: driveId),
        AppRoutePath.folderDetail(driveId: driveId, driveFolderId: folderId),
        AppRoutePath.sharedFile(sharedFileId: driveId),
        AppRoutePath.rawTransaction(txId: 'tx'),
      ]) {
        delegate = AppRouterDelegate();
        await delegate.setNewRoutePath(path);
        expect(delegate.signsInWhileChecking(checking), isFalse,
            reason: '$path');
      }
    });

    test('waits for the address to be read: a link looks like none before', () {
      expect(delegate.signsInWhileChecking(checking), isFalse);
    });

    test('leaves the get-started page to itself', () async {
      await delegate.setNewRoutePath(AppRoutePath.getStarted());
      expect(delegate.signsInWhileChecking(checking), isFalse);
    });

    test('is over once the check is', () async {
      await delegate.setNewRoutePath(AppRoutePath.unknown());
      expect(delegate.signsInWhileChecking(ProfilePromptAdd()), isFalse);
      expect(delegate.signsInWhileChecking(ProfilePromptLogIn()), isFalse);
    });

    test('never in a publication', () async {
      await delegate.setNewRoutePath(AppRoutePath.unknown());
      PublicationMode.debugSet('publication.json');
      expect(delegate.signsInWhileChecking(checking), isFalse);
    });
  });

  // A share page, then `#/` typed into the same tab: the route names nothing
  // a visitor can see, the profile does not change, so nothing sent them to
  // sign in and the builder had nothing to draw. The splash stayed up.
  group('an address changed in an open tab', () {
    ProfileCubit profileIn(ProfileState state) {
      final cubit = MockProfileCubit();
      when(() => cubit.state).thenReturn(state);
      return cubit;
    }

    final visitors = <String, ProfileState>{
      'with no account on the device': ProfilePromptAdd(),
      'with a remembered account': ProfilePromptLogIn(),
    };

    for (final MapEntry(key: who, value: state) in visitors.entries) {
      test('sends a visitor $who from a share page at / to sign in', () async {
        delegate.profileCubit = profileIn(state);
        await delegate.setNewRoutePath(
          AppRoutePath.sharedFile(sharedFileId: driveId),
        );
        expect(delegate.signingIn, isFalse);

        await delegate.setNewRoutePath(AppRoutePath.unknown());

        expect(delegate.signingIn, isTrue);
        expect(delegate.currentConfiguration.signingIn, isTrue);
      });

      test('sends a visitor $who to sign in for a page that needs an account',
          () async {
        for (final path in [
          AppRoutePath.drivesList(),
          AppRoutePath.names(),
          AppRoutePath.webPages(),
        ]) {
          delegate = AppRouterDelegate()..profileCubit = profileIn(state);
          await delegate.setNewRoutePath(path);
          expect(delegate.signingIn, isTrue, reason: '$path');
        }
      });
    }

    test('leaves a visitor on a page a visitor can see', () async {
      for (final path in [
        AppRoutePath.sharedFile(sharedFileId: driveId),
        AppRoutePath.rawTransaction(txId: 'tx'),
        AppRoutePath.driveDetail(driveId: driveId),
        AppRoutePath.getStarted(),
      ]) {
        delegate = AppRouterDelegate()
          ..profileCubit = profileIn(ProfilePromptAdd());
        await delegate.setNewRoutePath(path);
        expect(delegate.signingIn, isFalse, reason: '$path');
      }
    });

    test('leaves a signed-in user in the app', () async {
      delegate.profileCubit =
          profileIn(ProfileLoggedIn(user: getTestUser(), useTurbo: false));
      await delegate.setNewRoutePath(AppRoutePath.unknown());
      expect(delegate.signingIn, isFalse);
    });

    test('waits while the check for an account or a login runs', () async {
      for (final state in [ProfileCheckingAvailability(), ProfileLoggingIn()]) {
        delegate = AppRouterDelegate()..profileCubit = profileIn(state);
        await delegate.setNewRoutePath(
          AppRoutePath.driveDetail(driveId: driveId),
        );
        expect(delegate.signingIn, isFalse, reason: '$state');
      }
    });
  });
}

Drive _drive(String id) => Drive(
      id: id,
      name: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );
