import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/topbar/home_button.dart';
import 'package:ardrive/pages/app_route_path.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

/// The way back to the drives list, in the one slot that exists on every
/// screen and both breakpoints.
///
/// It was in the sidebar first - the wrong container, because the sidebar
/// already lists every drive - and then only in the explorer's breadcrumb,
/// which `_desktopView` alone builds, so a phone had no way back at all.
void main() {
  late MockProfileCubit profileCubit;
  late AppRouterDelegate delegate;

  setUp(() {
    profileCubit = MockProfileCubit();
    delegate = AppRouterDelegate();
  });

  Widget host() => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: MultiProvider(
            providers: [
              ListenableProvider<AppRouterDelegate>.value(value: delegate),
            ],
            child: BlocProvider<ProfileCubit>.value(
              value: profileCubit,
              child: const Scaffold(body: HomeButtonTopBar()),
            ),
          ),
        ),
      );

  void signedIn() => whenListen(
        profileCubit,
        const Stream<ProfileState>.empty(),
        initialState: ProfileLoggedIn(user: getTestUser(), useTurbo: false),
      );

  testWidgets('routes to the drives list', (tester) async {
    signedIn();
    await delegate.setNewRoutePath(
      AppRoutePath.driveDetail(driveId: 'drive-1'),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(delegate.showingDrivesList, isFalse,
        reason: 'precondition: a drive is open');

    await tester.tap(find.byType(HomeButtonTopBar));
    await tester.pumpAndSettle();

    expect(delegate.showingDrivesList, isTrue);
    expect(delegate.currentConfiguration.drivesList, isTrue,
        reason: 'the address bar has to agree with the screen');
  });

  testWidgets('and keeps working when the flag is already set', (tester) async {
    // The flag being true was never proof the list was on screen, and
    // returning early on it is how both the old nav entry and the breadcrumb
    // came to do nothing at all.
    signedIn();
    await delegate.setNewRoutePath(AppRoutePath.drivesList());
    delegate.signingIn = true;

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    var notified = 0;
    delegate.addListener(() => notified++);

    await tester.tap(find.byType(HomeButtonTopBar));
    await tester.pumpAndSettle();

    expect(notified, greaterThan(0),
        reason: 'a route that outranks the list must not swallow the tap');
    expect(delegate.signingIn, isFalse);
    expect(delegate.showingDrivesList, isTrue);
  });

  testWidgets('is not offered to a viewer who has no drives list',
      (tester) async {
    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfilePromptAdd());

    await delegate.setNewRoutePath(
      AppRoutePath.driveDetail(driveId: 'drive-1'),
    );

    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.home_outlined), findsNothing);
  });
}
