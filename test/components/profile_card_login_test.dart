import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/mocks.dart';

/// The top bar's "Log in" for a visitor.
///
/// It used to log out, which runs the router's `clearState` and drops the
/// drive the visitor was looking at, so their login landed on the drives list
/// without it. Viewing a drive, it now keeps the drive; otherwise it behaves
/// as before.
void main() {
  const driveId = 'a2b7ba0a-3b2a-4c1b-8a2f-6d1a0b3c4d5e';

  late MockProfileCubit profileCubit;
  late AppRouterDelegate delegate;

  setUp(() {
    profileCubit = MockProfileCubit();
    when(() => profileCubit.logoutProfile()).thenAnswer((_) async {});
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfilePromptAdd(),
    );
    delegate = AppRouterDelegate();
  });

  tearDown(() => delegate.clearState());

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
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
              ListenableProvider<AppRouterDelegate>.value(value: delegate),
            ],
            child: const Scaffold(body: ProfileCard()),
          ),
        ),
      ),
    );
  }

  testWidgets('while viewing a drive, goes to sign in and keeps the drive',
      (tester) async {
    delegate.openDriveAsVisitor(driveId: driveId);
    await pump(tester);

    await tester.tap(find.byKey(const Key('profileCardLogin')));
    await tester.pump();

    expect(delegate.signingIn, isTrue);
    expect(delegate.driveId, driveId);
    verifyNever(() => profileCubit.logoutProfile());
  });

  testWidgets('with no drive in view, logs out as before', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('profileCardLogin')));
    await tester.pump();

    verify(() => profileCubit.logoutProfile()).called(1);
    expect(delegate.signingIn, isFalse);
  });
}
