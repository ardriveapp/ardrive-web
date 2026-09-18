import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/new_button/new_button.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/components/dropdown_item.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/mocks.dart';

Drive _drive({required String ownerAddress}) => Drive(
      id: 'photos',
      rootFolderId: 'root-photos',
      ownerAddress: ownerAddress,
      name: 'Photos',
      privacy: 'private',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

/// What the New menu offers with no drive open, which is what the drives list
/// is, and in a drive nothing has read yet.
///
/// Two rules are held here. On the drives list the menu is about drives:
/// uploading, which leads to the drive the files will go to, and the drive
/// actions themselves. Everything that needs a folder stays out, because
/// there is no folder in sight.
///
/// Inside a drive the menu keeps its shape whether or not the app has read
/// that drive. It used to hold a single row, "Advanced", opening onto a
/// single action, which readers took for a broken app.
void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit driveDetailCubit;
  late MockArDriveAuth auth;

  setUp(() {
    profileCubit = MockProfileCubit();
    driveDetailCubit = MockDriveDetailCubit();
    auth = MockArDriveAuth();

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(user: fakeUserJson, useTurbo: true),
    );
    when(() => auth.currentUser).thenReturn(fakeUserJson);
  });

  Future<void> pumpMenu(
    WidgetTester tester, {
    bool bottomNavigation = false,
    DriveDetailState? state,
  }) async {
    // No drive open, unless a test says otherwise: what the drives list
    // route provides.
    final detailState = state ?? DriveDetailLoadInProgress();
    whenListen(
      driveDetailCubit,
      const Stream<DriveDetailState>.empty(),
      initialState: detailState,
    );

    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: RepositoryProvider<ArDriveAuth>.value(
            value: auth,
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ProfileCubit>.value(value: profileCubit),
                BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
              ],
              child: Scaffold(
                body: Center(
                  child: NewButton(
                    drive: null,
                    driveDetailState: detailState,
                    isBottomNavigationButton: bottomNavigation,
                    child: bottomNavigation ? null : const Text('open me'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The plus button draws its own control and opens a modal; the sidebar
    // menu wraps whatever child it is given.
    await tester.tap(
      bottomNavigation ? find.byType(ArDriveFAB) : find.text('open me'),
    );
    await tester.pumpAndSettle();
  }

  /// The same lookup `drives_list_menu_test.dart` uses: the tile picks its
  /// colours off this flag alone, so it is the flag that says whether a row is
  /// offered or drawn dead.
  ArDriveDropdownItemTile tile(WidgetTester tester, String name) =>
      tester.widget<ArDriveDropdownItemTile>(
        find.widgetWithText(ArDriveDropdownItemTile, name),
      );

  double top(WidgetTester tester, Finder finder) =>
      tester.getTopLeft(finder).dy;

  group('with no drive open', () {
    /// The one thing most people open this menu for.
    testWidgets('offers uploading', (tester) async {
      await pumpMenu(tester);

      expect(tile(tester, 'Upload File(s)').isDisabled, isFalse);
      expect(tile(tester, 'Upload Folder').isDisabled, isFalse);
    });

    testWidgets('offers a new drive', (tester) async {
      await pumpMenu(tester);

      expect(
        find.text('New Drive'),
        findsOneWidget,
        reason: 'it was gated on the drive list having loaded, which creating '
            'a drive does not depend on',
      );
    });

    /// A wallet that cannot pay is not a reason to withhold the action. The
    /// dialog behind it says there is not enough AR and offers to top up,
    /// which is more use than a control that does nothing, and it matches the
    /// getting started cards, which open the same dialog ungated.
    testWidgets('offers a new drive even when the wallet cannot pay',
        (tester) async {
      when(() => profileCubit.state).thenReturn(
        // Zero balance, and no Turbo to fall back on.
        ProfileLoggedIn(user: fakeUserJson, useTurbo: false),
      );

      await pumpMenu(tester);

      expect(tile(tester, 'New Drive').isDisabled, isFalse);
    });

    /// One action behind a submenu row is a menu that looks empty.
    testWidgets('puts attaching a drive at the top level', (tester) async {
      await pumpMenu(tester);

      expect(find.text('Attach Drive'), findsOneWidget);
      expect(find.text('Advanced'), findsNothing);
    });

    testWidgets('leads with uploading, ruled off from the drive actions',
        (tester) async {
      await pumpMenu(tester);

      final upload = top(tester, find.text('Upload Folder'));
      final rule = top(tester, find.byType(Divider).first);
      final newDrive = top(tester, find.text('New Drive'));

      expect(upload, lessThan(rule));
      expect(rule, lessThan(newDrive));
    });
  });

  /// The mobile plus button keeps the same rules. The drive page only draws it
  /// once its drive has loaded, so these hold it in step with the sidebar
  /// rather than describe a state it reaches today.
  group('on the mobile plus button, with no drive open', () {
    testWidgets('offers the same actions', (tester) async {
      await pumpMenu(tester, bottomNavigation: true);

      expect(find.text('Upload File(s)'), findsOneWidget);
      expect(find.text('Upload Folder'), findsOneWidget);
      expect(find.text('New Drive'), findsOneWidget);
      expect(find.text('Attach Drive'), findsOneWidget);
      expect(find.text('Advanced'), findsNothing);
    });

    /// A rule with nothing above it drew a hairline across the top of the
    /// sheet before its first item.
    testWidgets('opens with an item rather than a rule', (tester) async {
      await pumpMenu(tester, bottomNavigation: true);

      expect(
        top(tester, find.text('Upload File(s)')),
        lessThan(top(tester, find.byType(Divider).first)),
      );
    });
  });

  /// The menu keeps its shape whether or not the app has read the drive.
  /// "Synced" is the app's word, and a menu that grows items after a sync
  /// teaches the reader only that it is unpredictable.
  group('in a drive nothing has read yet', () {
    testWidgets('offers the folder actions too', (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      for (final action in ['New Folder', 'New Note', 'New File Pin']) {
        expect(tile(tester, action).isDisabled, isFalse, reason: action);
      }
    });

    /// They only make sense inside a drive: on the drives list there is no
    /// folder for any of them to go into.
    testWidgets('which the drives list does not offer at all', (tester) async {
      await pumpMenu(tester);

      expect(find.text('New Folder'), findsNothing);
      expect(find.text('New Note'), findsNothing);
      expect(find.text('New File Pin'), findsNothing);
    });

    /// Uploading there leads to its sync first, so it is offered.
    testWidgets('offers uploading into your own drive', (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: fakeUserJson.walletAddress),
        ),
      );

      expect(tile(tester, 'Upload File(s)').isDisabled, isFalse);
    });

    /// Syncing somebody else's drive would only arrive at the same answer.
    testWidgets("keeps somebody else's drive read-only", (tester) async {
      await pumpMenu(
        tester,
        state: DriveDetailLoadUnsynced(
          drive: _drive(ownerAddress: 'somebody-else'),
        ),
      );

      expect(tile(tester, 'Upload File(s)').isDisabled, isTrue);
      expect(tile(tester, 'Upload Folder').isDisabled, isTrue);
    });
  });
}
