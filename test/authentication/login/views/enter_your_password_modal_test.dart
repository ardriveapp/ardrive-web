import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

class _MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

/// What the screen says while it is proving the password.
///
/// Proving it is not instant: it finds a private drive transaction, reads that
/// drive's signature from the gateway, derives a key, then fetches and
/// decrypts the drive entity. On a slow gateway that runs to several seconds.
///
/// `LoginBloc` has always reported the phase as `LoginCheckingPassword`. The
/// only thing this screen did with it was disable the field and grey the
/// button - which from the reader's side is indistinguishable from a press
/// that never registered, and is exactly how it was reported.
void main() {
  late _MockLoginBloc loginBloc;
  late _MockProfileNameBloc profileNameBloc;
  late _MockUserPreferencesRepository userPreferences;
  late MockArDriveAuth auth;
  late MockBiometricAuthentication biometrics;

  // The event type is sealed, so a real one stands in for `captureAny`.
  setUpAll(() => registerFallbackValue(const CleanProfileName()));

  setUp(() {
    loginBloc = _MockLoginBloc();
    profileNameBloc = _MockProfileNameBloc();
    userPreferences = _MockUserPreferencesRepository();

    // The settings submenu in this screen's header reads it; nothing this
    // test asserts on depends on what it says.
    when(() => userPreferences.watch())
        .thenAnswer((_) => const Stream<UserPreferences>.empty());
    when(() => userPreferences.currentPreferences).thenReturn(null);

    auth = MockArDriveAuth();
    when(() => auth.getWalletAddress()).thenAnswer((_) async => null);
    biometrics = MockBiometricAuthentication();
    // The biometric toggle asks whether the device can offer it at all. No,
    // so the toggle draws nothing and stays out of what this test asserts on.
    when(() => biometrics.checkDeviceSupport()).thenAnswer((_) async => false);
    when(() => biometrics.isEnabled()).thenAnswer((_) async => false);
    when(() => biometrics.enabledStream)
        .thenAnswer((_) => const Stream<bool>.empty());

    whenListen(
      loginBloc,
      const Stream<LoginState>.empty(),
      initialState: LoginCheckingPassword(),
    );
    whenListen(
      profileNameBloc,
      const Stream<ProfileNameState>.empty(),
      initialState: const ProfileNameInitial(null),
    );
  });

  Widget passwordScreen({
    required bool checkingPassword,
    ArDriveThemeData? theme,
    bool showModal = true,
  }) =>
      ArDriveTheme(
        themeData: theme ?? lightTheme(),
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
              BlocProvider<LoginBloc>.value(value: loginBloc),
              BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
              RepositoryProvider<UserPreferencesRepository>.value(
                value: userPreferences,
              ),
              RepositoryProvider<ArDriveAuth>.value(value: auth),
              RepositoryProvider<BiometricAuthentication>.value(
                value: biometrics,
              ),
            ],
            child: Scaffold(
              body: showModal
                  ? EnterYourPasswordWidget(
                      loginBloc: loginBloc,
                      showWalletCreated: false,
                      alreadyLoggedIn: true,
                      checkingPassword: checkingPassword,
                      passwordFailed: false,
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      );

  Future<void> pumpPasswordScreen(
    WidgetTester tester, {
    required bool checkingPassword,
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
              BlocProvider<LoginBloc>.value(value: loginBloc),
              BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
              RepositoryProvider<UserPreferencesRepository>.value(
                value: userPreferences,
              ),
              RepositoryProvider<ArDriveAuth>.value(value: auth),
              RepositoryProvider<BiometricAuthentication>.value(
                value: biometrics,
              ),
            ],
            child: Scaffold(
              body: EnterYourPasswordWidget(
                loginBloc: loginBloc,
                showWalletCreated: false,
                alreadyLoggedIn: true,
                checkingPassword: checkingPassword,
                passwordFailed: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('says what it is doing while the password is being proved',
      (tester) async {
    await pumpPasswordScreen(tester, checkingPassword: true);

    expect(
      find.text('Checking your password...'),
      findsOneWidget,
      reason: 'a greyed-out button on its own reads as a press that did not '
          'register, for as long as the gateway takes',
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('and offers to continue when it is not', (tester) async {
    await pumpPasswordScreen(tester, checkingPassword: false);

    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Checking your password...'), findsNothing);
    expect(
      find.byType(CircularProgressIndicator),
      findsNothing,
      reason: 'nothing is happening yet, so nothing should suggest it is',
    );
  });

  /// The dialog closes as soon as the login succeeds, and the wallet address
  /// the modal asks for can still be on its way from the database. Reading
  /// `context` after that threw in release builds ("Null check operator used
  /// on a null value"), seen after a reload with the web database in a worker.
  group('the profile name the modal asks for', () {
    testWidgets('still loads, without an error, when the modal is gone first',
        (tester) async {
      final address = Completer<String?>();
      when(() => auth.getWalletAddress()).thenAnswer((_) => address.future);
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(passwordScreen(checkingPassword: false));
      await tester.pump();
      // The login succeeded and the dialog closed.
      await tester.pumpWidget(
          passwordScreen(checkingPassword: false, showModal: false));
      await tester.pump();

      address.complete('the-wallet-address');
      await tester.pump();

      expect(tester.takeException(), isNull);
      final asked = verify(() => profileNameBloc.add(captureAny())).captured;
      expect(asked, hasLength(1));
      expect((asked.single as LoadProfileNameBeforeLogin).walletAddress,
          'the-wallet-address');
    });

    testWidgets('is asked for once, however often its dependencies change',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(passwordScreen(checkingPassword: false));
      await tester.pump();
      await tester.pumpWidget(passwordScreen(
          checkingPassword: false,
          theme: ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())));
      await tester.pump();
      await tester.pumpWidget(passwordScreen(checkingPassword: false));
      await tester.pump();

      verify(() => auth.getWalletAddress()).called(1);
    });
  });
}
