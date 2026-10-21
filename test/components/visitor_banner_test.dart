import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/banners/visitor_banner.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/mocks.dart';

/// The one line a visitor sees above the explorer, and the one thing it does.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';

  late MockProfileCubit profileCubit;
  late AppRouterDelegate delegate;

  setUp(() {
    VisitorBanner.dismissedThisSession = false;
    profileCubit = MockProfileCubit();
    delegate = AppRouterDelegate();
    delegate.openDriveAsVisitor(driveId: driveId);
  });

  tearDown(() {
    VisitorBanner.dismissedThisSession = false;
    delegate.clearState();
  });

  Future<void> pump(WidgetTester tester, ProfileState profile) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: profile,
    );

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
              ListenableProvider<AppRouterDelegate>.value(value: delegate),
            ],
            child: const Scaffold(body: VisitorBanner()),
          ),
        ),
      ),
    );
  }

  testWidgets('is shown to a visitor', (tester) async {
    await pump(tester, ProfilePromptAdd());

    expect(find.byKey(const Key('visitorBanner')), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('is not shown to a signed-in user', (tester) async {
    await pump(
      tester,
      ProfileLoggedIn(user: fakeUserJson, useTurbo: false),
    );

    expect(find.byKey(const Key('visitorBanner')), findsNothing);
  });

  testWidgets('Sign in goes to the sign-in page and keeps the drive',
      (tester) async {
    await pump(tester, ProfilePromptAdd());

    await tester.tap(find.byKey(const Key('visitorBannerSignIn')));
    await tester.pump();

    expect(delegate.signingIn, isTrue);
    expect(delegate.driveId, driveId);
  });

  testWidgets('dismissing it keeps it away for the session', (tester) async {
    await pump(tester, ProfilePromptAdd());

    await tester.tap(find.byKey(const Key('visitorBannerDismiss')));
    await tester.pump();

    expect(find.byKey(const Key('visitorBanner')), findsNothing);
    expect(VisitorBanner.dismissedThisSession, isTrue);

    // Built again, as moving to another drive would: still gone.
    await pump(tester, ProfilePromptAdd());
    expect(find.byKey(const Key('visitorBanner')), findsNothing);
  });
}
