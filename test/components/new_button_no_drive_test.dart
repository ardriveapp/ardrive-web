import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/new_button/new_button.dart';
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

/// What the New menu offers with no drive open, which is what the drives list
/// is.
///
/// Every other item in that menu needs a drive: uploads, folders, notes, pins,
/// manifests, snapshots. On the drives list they all drop out, correctly, and
/// what was left was a single row, "Advanced", holding a single action. Users
/// read an app offering no options as a broken one.
void main() {
  late MockProfileCubit profileCubit;
  late MockDriveDetailCubit driveDetailCubit;

  setUp(() {
    profileCubit = MockProfileCubit();
    driveDetailCubit = MockDriveDetailCubit();

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(user: fakeUserJson, useTurbo: true),
    );

    // No drive open: what the drives list route provides.
    whenListen(
      driveDetailCubit,
      const Stream<DriveDetailState>.empty(),
      initialState: DriveDetailLoadInProgress(),
    );
  });

  Future<void> pumpMenu(
    WidgetTester tester, {
    bool bottomNavigation = false,
  }) async {
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
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: profileCubit),
              BlocProvider<DriveDetailCubit>.value(value: driveDetailCubit),
            ],
            child: Scaffold(
              body: Center(
                child: NewButton(
                  drive: null,
                  driveDetailState: DriveDetailLoadInProgress(),
                  isBottomNavigationButton: bottomNavigation,
                  child: bottomNavigation ? null : const Text('open me'),
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

  testWidgets('offers a new drive with no drive open', (tester) async {
    await pumpMenu(tester);

    expect(
      find.text('New Drive'),
      findsOneWidget,
      reason: 'it was gated on the drive list having loaded, which creating a '
          'drive does not depend on',
    );
  });

  /// One action behind a submenu row is a menu that looks empty.
  testWidgets('and puts attaching a drive at the top level', (tester) async {
    await pumpMenu(tester);

    expect(find.text('Attach Drive'), findsOneWidget);
    expect(find.text('Advanced'), findsNothing);
  });

  /// The same menu on mobile, which is the plus button on a drive page. It
  /// lands here only while that drive has not loaded or cannot be read, and
  /// the rule is the reader's, not the surface's.
  testWidgets('and does the same on the mobile plus button', (tester) async {
    await pumpMenu(tester, bottomNavigation: true);

    expect(find.text('New Drive'), findsOneWidget);
    expect(find.text('Attach Drive'), findsOneWidget);
    expect(find.text('Advanced'), findsNothing);
  });

  /// The rule between two groups, with nothing above it. The group it used to
  /// separate is empty with no drive open, so it drew a hairline across the top
  /// of the sheet before the first item.
  testWidgets('and opens with an item rather than a rule', (tester) async {
    await pumpMenu(tester, bottomNavigation: true);

    expect(find.byType(Divider), findsNothing);
  });
}
