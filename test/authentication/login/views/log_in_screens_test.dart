import 'dart:typed_data';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/authentication/login/views/creating_account_view.dart';
import 'package:ardrive/authentication/login/views/enter_recovery_phrase_view.dart';
import 'package:ardrive/authentication/login/views/landing_view.dart';
import 'package:ardrive/authentication/login/views/log_in_view.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/authentication/login/views/modals/enter_your_password_modal.dart';
import 'package:ardrive/authentication/login/views/wallet_wait_view.dart';
import 'package:ardrive/authentication/login/views/welcome_back_view.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/theme/theme_switcher_bloc.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user_preferences.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../../test_utils/utils.dart';

class _MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

Future<IOFile> _file(String text) => IOFile.fromData(
      Uint8List.fromList(text.codeUnits),
      name: 'file.json',
      lastModifiedDate: DateTime(2026),
    );

void main() {
  late _MockLoginBloc loginBloc;
  late _MockProfileNameBloc profileNameBloc;
  late MockBiometricAuthentication biometrics;
  late _MockUserPreferencesRepository userPreferences;
  late MockArDriveAuth auth;

  setUpAll(() async {
    registerFallbackValue(const CleanProfileName());
    registerFallbackValue(const ShowLanding());
    registerFallbackValue(await _file('x'));
  });

  setUp(() {
    loginBloc = _MockLoginBloc();
    profileNameBloc = _MockProfileNameBloc();
    biometrics = MockBiometricAuthentication();
    userPreferences = _MockUserPreferencesRepository();
    auth = MockArDriveAuth();
    when(() => auth.getWalletAddress()).thenAnswer((_) async => null);
    when(() => userPreferences.watch())
        .thenAnswer((_) => const Stream<UserPreferences>.empty());
    when(() => userPreferences.currentPreferences).thenReturn(null);
    when(() => biometrics.checkDeviceSupport()).thenAnswer((_) async => false);
    when(() => biometrics.isEnabled()).thenAnswer((_) async => false);
    when(() => biometrics.enabledStream)
        .thenAnswer((_) => const Stream<bool>.empty());
    whenListen(loginBloc, const Stream<LoginState>.empty(),
        initialState: const LoginInitial(
            isArConnectAvailable: false, existingUserFlow: true));
    whenListen(profileNameBloc, const Stream<ProfileNameState>.empty(),
        initialState: const ProfileNameInitial(null));
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      // Above the app, as in main.dart, so dialogs can read them too.
      MultiBlocProvider(
        providers: [
          BlocProvider<LoginBloc>.value(value: loginBloc),
          BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
          RepositoryProvider<BiometricAuthentication>.value(value: biometrics),
          RepositoryProvider<ArDriveAuth>.value(value: auth),
          RepositoryProvider<UserPreferencesRepository>.value(
              value: userPreferences),
          ChangeNotifierProvider<ActivityTracker>(
            create: (_) => ActivityTracker(),
          ),
        ],
        child: ArDriveApp(
          builder: (context) => MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  List<LoginEvent> added() =>
      verify(() => loginBloc.add(captureAny())).captured.cast<LoginEvent>();

  /// The version is in Help, not under "Open a drive without logging in".
  testWidgets('the landing says no version', (tester) async {
    await pump(tester, const LandingView());

    expect(find.byKey(const Key('openDriveLandingLink')), findsOneWidget);
    expect(find.textContaining('Version'), findsNothing);
  });

  group('which panel', () {
    test('the account on this device is unlocked in the panel', () {
      expect(
          loginPanelFor(const PromptPassword(alreadyLoggedIn: true), loginBloc),
          isA<WelcomeBackView>());
      expect(loginPanelRebuildsOn(const PromptPassword(alreadyLoggedIn: true)),
          isTrue);
    });

    testWidgets(
        'the account on this device gets no password dialog over the panel; '
        'a wallet just chosen does', (tester) async {
      await pump(
        tester,
        Builder(
          builder: (context) => Column(children: [
            TextButton(
              onPressed: () => handleLoginState(
                  context, const PromptPassword(alreadyLoggedIn: true)),
              child: const Text('reload'),
            ),
            TextButton(
              onPressed: () => handleLoginState(
                  context, PromptPassword(wallet: getTestWallet())),
              child: const Text('keyfile'),
            ),
          ]),
        ),
      );
      await tester.tap(find.text('reload'));
      await tester.pumpAndSettle();
      expect(find.byType(EnterYourPasswordWidget), findsNothing);

      await tester.tap(find.text('keyfile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(EnterYourPasswordWidget), findsOneWidget);
    });

    test('a password for a wallet just chosen leaves the panel as it was', () {
      expect(loginPanelRebuildsOn(const PromptPassword()), isFalse);
    });

    test('errors and dialogs leave the panel as it was', () {
      for (final state in [
        const GatewayLoginFailure('down', 'https://gateway'),
        const LoginUnknownFailure('x'),
        const LoginFailure('x'),
        const LoginShowBlockingDialog(message: 'm'),
        LoginShowLoader(),
        LoginCloseBlockingDialog(),
        LoginCheckingPassword(),
        LoginPasswordFailed(),
        LoginPasswordFailedWithPrivateDriveNotFound(),
      ]) {
        expect(loginPanelRebuildsOn(state), isFalse, reason: '$state');
      }
    });

    test('each step has its panel', () {
      when(() => loginBloc.isArConnectAvailable).thenReturn(false);
      when(() => loginBloc.isMetamaskAvailable).thenReturn(false);
      when(() => loginBloc.isSolanaAvailable).thenReturn(false);
      expect(
          loginPanelFor(
              const LoginInitial(
                  isArConnectAvailable: false, existingUserFlow: true),
              loginBloc),
          isA<LogInView>());
      expect(loginPanelFor(const LoginEnterRecoveryPhrase(), loginBloc),
          isA<EnterRecoveryPhraseView>());
      expect(
          loginPanelFor(
              const LoginWaitingOnWallet(wallet: BrowserWallet.wander),
              loginBloc),
          isA<WalletWaitView>());
    });
  });

  group('Log in', () {
    Widget logIn({bool ar = false, bool eth = false, bool sol = false}) =>
        LogInView(
          isArConnectAvailable: ar,
          isMetamaskAvailable: eth,
          isSolanaAvailable: sol,
        );

    testWidgets('says what it is for, and offers the phrase or keyfile',
        (tester) async {
      await pump(tester, logIn());
      expect(find.text('Log in'), findsOneWidget);
      expect(
          find.text('Use the account you made with ArDrive, '
              'or a wallet you already have.'),
          findsOneWidget);
      expect(find.text('Recovery phrase or keyfile'), findsOneWidget);
      expect(find.text('or a browser wallet'), findsNothing,
          reason: 'no wallet is installed, so none is offered');
      expect(find.byType(LogInOption), findsOneWidget);
    });

    testWidgets('offers only the wallets that are installed', (tester) async {
      await pump(tester, logIn(ar: true, eth: true));
      expect(find.text('or a browser wallet'), findsOneWidget);
      expect(find.text('Wander'), findsOneWidget);
      expect(find.text('MetaMask'), findsOneWidget);
      expect(find.text('Phantom or Solflare'), findsNothing);

      await pump(tester, logIn(sol: true));
      expect(find.text('Phantom or Solflare'), findsOneWidget);
      expect(find.text('Wander'), findsNothing);
    });

    testWidgets('each option and link does what it says', (tester) async {
      await pump(tester, logIn(ar: true, eth: true));
      await tester.tap(find.text('Recovery phrase or keyfile'));
      await tester.tap(find.text('Wander'));
      await tester.tap(find.text('MetaMask'));
      await tester.tap(find.byKey(const Key('logInBack')));
      await tester.tap(find.byKey(const Key('logInCreateAccount')));
      final events = added();
      expect(events[0], isA<EnterSeedPhrase>());
      expect(events[1], isA<AddWalletFromArConnect>());
      expect(events[2], isA<LoginWithMetamask>());
      expect(events[3], isA<ShowLanding>());
      // Sign up's choice, which offers a wallet if there is one, and whose
      // Back comes back here.
      expect(events[4], const StartSignUp(fromLogIn: true));
    });
  });

  group('Sign up with a wallet in the browser', () {
    Widget signUp({bool ar = false, bool eth = false, bool sol = false}) =>
        LogInView(
          signUp: true,
          isArConnectAvailable: ar,
          isMetamaskAvailable: eth,
          isSolanaAvailable: sol,
        );

    testWidgets('offers a new account first, then the wallets found',
        (tester) async {
      await pump(tester, signUp(ar: true, sol: true));
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Create an account'), findsOneWidget);
      expect(find.text('or use a wallet you already have'), findsOneWidget);
      expect(find.text('Wander'), findsOneWidget);
      expect(find.text('Phantom or Solflare'), findsOneWidget);
      expect(find.text('MetaMask'), findsNothing);
      expect(find.text('Recovery phrase or keyfile'), findsNothing);
      expect(
          find.textContaining('Already have an account?', findRichText: true),
          findsOneWidget);
      expect(find.byKey(const Key('signUpLogIn')), findsOneWidget);
      expect(
          tester.widget<ArDriveLink>(find.byKey(const Key('signUpLogIn'))).text,
          'Log in');
    });

    testWidgets('each row and link does what it says', (tester) async {
      await pump(tester, signUp(ar: true, eth: true));
      await tester.tap(find.text('Create an account'));
      await tester.tap(find.text('Wander'));
      await tester.tap(find.text('MetaMask'));
      await tester.tap(find.byKey(const Key('logInBack')));
      await tester.tap(find.byKey(const Key('signUpLogIn')));
      final events = added();
      expect(events[0], isA<CreateNewWallet>());
      expect(events[1], isA<AddWalletFromArConnect>());
      expect(events[2], isA<LoginWithMetamask>());
      expect(events[3], isA<ShowLanding>());
      expect(events[4], const SelectLoginFlow(existingUser: true));
    });

    testWidgets('Back returns to Log in when it came from there',
        (tester) async {
      await pump(
          tester,
          const LogInView(
            signUp: true,
            backToLogIn: true,
            isArConnectAvailable: true,
            isMetamaskAvailable: false,
            isSolanaAvailable: false,
          ));
      await tester.tap(find.byKey(const Key('logInBack')));
      expect(added().single, const SelectLoginFlow(existingUser: true));
    });

    test('the panel follows the flow', () {
      when(() => loginBloc.signUpFromLogIn).thenReturn(false);
      when(() => loginBloc.isArConnectAvailable).thenReturn(true);
      when(() => loginBloc.isMetamaskAvailable).thenReturn(false);
      when(() => loginBloc.isSolanaAvailable).thenReturn(false);
      final choice = loginPanelFor(
          const LoginInitial(
              isArConnectAvailable: true, existingUserFlow: false),
          loginBloc) as LogInView;
      expect(choice.signUp, isTrue);
      expect(choice.backToLogIn, isFalse);
      when(() => loginBloc.signUpFromLogIn).thenReturn(true);
      expect(
          (loginPanelFor(
                  const LoginInitial(
                      isArConnectAvailable: true, existingUserFlow: false),
                  loginBloc) as LogInView)
              .backToLogIn,
          isTrue);
      final logIn = loginPanelFor(
          const LoginInitial(
              isArConnectAvailable: true, existingUserFlow: true),
          loginBloc) as LogInView;
      expect(logIn.signUp, isFalse);
      expect(
          (loginPanelFor(const LoginCreatingAccount(noWalletFound: true),
                  loginBloc) as CreatingAccountView)
              .noWalletFound,
          isTrue);
    });
  });

  group('the get-started link', () {
    Future<void> pumpPage(WidgetTester tester, LoginState state) async {
      final preferences = _MockUserPreferencesRepository();
      when(() => preferences.watch())
          .thenAnswer((_) => const Stream<UserPreferences>.empty());
      when(() => preferences.currentPreferences).thenReturn(null);
      when(() => loginBloc.isArConnectAvailable).thenReturn(true);
      when(() => loginBloc.isMetamaskAvailable).thenReturn(false);
      when(() => loginBloc.isSolanaAvailable).thenReturn(false);
      when(() => loginBloc.existingUserFlow).thenReturn(false);
      when(() => loginBloc.signUpFromLogIn).thenReturn(false);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<LoginBloc>.value(value: loginBloc),
            BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
            RepositoryProvider<UserPreferencesRepository>.value(
                value: preferences),
            BlocProvider<ThemeSwitcherBloc>(
              create: (_) =>
                  ThemeSwitcherBloc(userPreferencesRepository: preferences),
            ),
          ],
          child: ArDriveApp(
            builder: (context) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: LoginPageScaffold(
                isGettingStartedLoading: !gettingStartedReady(state),
                loginState: state,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('shows the choice, not a spinner, when a wallet is found',
        (tester) async {
      const choice =
          LoginInitial(isArConnectAvailable: true, existingUserFlow: false);
      whenListen(loginBloc, const Stream<LoginState>.empty(),
          initialState: choice);
      await pumpPage(tester, choice);
      expect(find.text('Create your account'), findsOneWidget);
      expect(find.text('Wander'), findsOneWidget);
    });

    testWidgets('goes to Creating, with the line, when none is',
        (tester) async {
      const creating = LoginCreatingAccount(noWalletFound: true);
      whenListen(loginBloc, const Stream<LoginState>.empty(),
          initialState: creating);
      await pumpPage(tester, creating);
      expect(
          find.text("No wallet found in this browser, so we're making one "
              'for you.'),
          findsOneWidget);
    });

    test('waits only while the account check runs', () {
      expect(gettingStartedReady(LoginLoading()), isFalse);
      expect(
          gettingStartedReady(const LoginInitial(
              isArConnectAvailable: true, existingUserFlow: false)),
          isTrue);
    });
  });

  group('Creating your account', () {
    const line =
        "No wallet found in this browser, so we're making one for you.";

    testWidgets('says why when no wallet was found', (tester) async {
      await pump(tester, const CreatingAccountView(noWalletFound: true));
      expect(find.text(line), findsOneWidget);
    });

    testWidgets('says nothing of wallets when a new account was chosen',
        (tester) async {
      await pump(tester, const CreatingAccountView());
      expect(find.text(line), findsNothing);
    });
  });

  testWidgets('Sign up on the first panel starts sign-up', (tester) async {
    when(() => loginBloc.anyWalletDetected).thenReturn(false);
    await pump(tester, const LandingView());
    await tester.tap(find.text('Sign up'));
    expect(added().single, isA<StartSignUp>());
  });

  group('Enter your recovery phrase', () {
    Future<void> enter(WidgetTester tester, String phrase) async {
      await tester.enterText(find.byType(EditableText), phrase);
      await tester.tap(find.byKey(const Key('phraseContinue')));
      await tester.pump();
    }

    testWidgets(
        'the phrase is a secret but not a password: hidden on screen and '
        'to screen readers, and never suggested or corrected', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, const EnterRecoveryPhraseView());
      await tester.enterText(find.byType(EditableText), 'river lantern');
      await tester.pump();

      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.obscureText, isFalse,
          reason: 'a password field has the browser offer to save it');
      expect(field.maxLines, greaterThan(1));
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
      expect(field.autofillHints, anyOf(isNull, isEmpty));

      String value() => tester.getSemantics(find.byType(EditableText)).value;
      expect(value(), isNot(contains('river')));
      expect(value(), '\u2022' * 'river lantern'.length);
      final span = field.controller.buildTextSpan(
          context: tester.element(find.byType(EditableText)),
          style: const TextStyle(color: Color(0xFF000000)),
          withComposing: false);
      expect(span.style!.color!.opacity, 0, reason: 'only the blur is drawn');

      await tester.tap(find.byKey(const Key('phraseShow')));
      await tester.pump();
      expect(find.text('Hide'), findsOneWidget);
      expect(value(), 'river lantern');
      handle.dispose();
    });

    testWidgets('says what is wrong with a phrase, and sends none',
        (tester) async {
      await pump(tester, const EnterRecoveryPhraseView());
      await enter(tester, '');
      expect(find.text('Enter your 12 words.'), findsOneWidget);
      await enter(tester, 'abandon abandon abandon');
      expect(find.text('Enter every word of your recovery phrase.'),
          findsOneWidget);
      await enter(tester, List.filled(12, 'abandon').join(' '));
      expect(find.text("That isn't a recovery phrase. Check each word."),
          findsOneWidget);
      verifyNever(() => loginBloc.add(any()));
    });

    testWidgets('sends a valid phrase as one line of lower-case words',
        (tester) async {
      final phrase = bip39.generateMnemonic();
      await pump(tester, const EnterRecoveryPhraseView());
      await enter(tester, '  ${phrase.toUpperCase().replaceAll(' ', '   ')}\n');
      final sent = added().single as AddWalletFromSeedPhraseLogin;
      expect(sent.mnemonic, phrase);
    });

    testWidgets('a file that is not a keyfile says so', (tester) async {
      final notes = await tester.runAsync(() => _file('my notes'));
      when(() => loginBloc.validateAndReturnWalletFile(any()))
          .thenAnswer((_) async => null);
      await pump(
          tester, EnterRecoveryPhraseView(pickKeyfile: () async => notes!));
      await tester.tap(find.byKey(const Key('phraseChooseKeyfile')));
      await tester.pump();
      expect(
          find.text("That file isn't a keyfile. Choose the keyfile you saved."),
          findsOneWidget);
      verifyNever(() => loginBloc.add(any()));
    });

    testWidgets('a keyfile goes on to the password', (tester) async {
      final keyfile = await tester.runAsync(() => _file(getWalletString));
      when(() => loginBloc.validateAndReturnWalletFile(any()))
          .thenAnswer((_) async => getTestWallet());
      await pump(
          tester, EnterRecoveryPhraseView(pickKeyfile: () async => keyfile!));
      await tester.tap(find.byKey(const Key('phraseChooseKeyfile')));
      await tester.pump();
      expect(added().single, isA<AddWalletFile>());
    });

    testWidgets('closing the file picker does nothing', (tester) async {
      await pump(
          tester,
          EnterRecoveryPhraseView(
              pickKeyfile: () async => throw ActionCanceledException()));
      await tester.tap(find.byKey(const Key('phraseChooseKeyfile')));
      await tester.pump();
      expect(find.textContaining("isn't a keyfile"), findsNothing);
      verifyNever(() => loginBloc.add(any()));
    });

    testWidgets('Back goes to Log in', (tester) async {
      await pump(tester, const EnterRecoveryPhraseView());
      await tester.tap(find.byKey(const Key('phraseBack')));
      expect(added().single, const SelectLoginFlow(existingUser: true));
    });
  });

  group('the phrase panel on a narrow phone with the keyboard up', () {
    for (final size in const [Size(360, 640), Size(375, 667)]) {
      testWidgets('fits at ${size.width.toInt()} wide, error showing',
          (tester) async {
        final preferences = _MockUserPreferencesRepository();
        when(() => preferences.watch())
            .thenAnswer((_) => const Stream<UserPreferences>.empty());
        when(() => preferences.currentPreferences).thenReturn(null);
        whenListen(loginBloc, const Stream<LoginState>.empty(),
            initialState: const LoginEnterRecoveryPhrase());
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.view.viewInsets = const FakeViewPadding(bottom: 300);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MultiBlocProvider(
            providers: [
              BlocProvider<LoginBloc>.value(value: loginBloc),
              BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
              RepositoryProvider<UserPreferencesRepository>.value(
                  value: preferences),
              BlocProvider<ThemeSwitcherBloc>(
                create: (_) =>
                    ThemeSwitcherBloc(userPreferencesRepository: preferences),
              ),
            ],
            child: ArDriveApp(
              builder: (context) => const MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: LoginPageScaffold(loginState: LoginEnterRecoveryPhrase()),
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);

        final continueButton = find.byKey(const Key('phraseContinue'));
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'the panel must scroll, not overflow');
        expect(find.text('Enter your 12 words.'), findsOneWidget);

        final keyfile = find.byKey(const Key('phraseChooseKeyfile'));
        await tester.ensureVisible(keyfile);
        await tester.pumpAndSettle();
        expect(tester.getRect(keyfile).bottom,
            lessThanOrEqualTo(size.height - 300));
      });
    }
  });

  group('Approve in your wallet', () {
    final cases = {
      BrowserWallet.wander: 'Wander',
      BrowserWallet.metamask: 'MetaMask',
      BrowserWallet.phantom: 'Phantom',
      BrowserWallet.solflare: 'Solflare',
    };
    for (final MapEntry(key: wallet, value: name) in cases.entries) {
      testWidgets('names $name', (tester) async {
        await pump(
            tester,
            WalletWaitView(
                wallet: wallet, request: BrowserWalletRequest.connect));
        expect(find.text('Approve in $name'), findsOneWidget);
        expect(
            find.text('$name asks you to connect to ArDrive. '
                'Approve it there to continue.'),
            findsOneWidget);
      });
    }

    testWidgets('says when it is a sign in rather than a connection',
        (tester) async {
      await pump(
          tester,
          const WalletWaitView(
              wallet: BrowserWallet.phantom,
              request: BrowserWalletRequest.signIn));
      expect(
          find.text('Phantom asks you to sign in to ArDrive. '
              'Approve it there to continue.'),
          findsOneWidget);
    });

    testWidgets('another Solana wallet is "your wallet"', (tester) async {
      await pump(
          tester,
          const WalletWaitView(
              wallet: BrowserWallet.otherSolana,
              request: BrowserWalletRequest.connect));
      expect(find.text('Approve in your wallet'), findsOneWidget);
    });

    testWidgets('Cancel cancels', (tester) async {
      await pump(
          tester,
          const WalletWaitView(
              wallet: BrowserWallet.wander,
              request: BrowserWalletRequest.connect));
      await tester.tap(find.byKey(const Key('walletWaitCancel')));
      expect(added().single, isA<CancelWalletLogin>());
    });
  });

  group('Welcome back', () {
    testWidgets('unlocks with the password', (tester) async {
      await pump(tester, const WelcomeBackView());
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.text('Enter your password to open your drives.'),
          findsOneWidget);
      bool disabled() => tester
          .widget<ArDriveButtonNew>(find.byKey(const Key('welcomeBackLogIn')))
          .isDisabled;
      expect(disabled(), isTrue);
      await tester.enterText(find.byType(EditableText), 'secret');
      await tester.pump();
      expect(disabled(), isFalse);
      await tester.tap(find.byKey(const Key('welcomeBackLogIn')));
      expect(added().single, const UnlockUserWithPassword(password: 'secret'));
    });

    const address = 'iKryOeZQMONi2965nKz528htMMN_sB0123456789oRjA';

    testWidgets('says which account it unlocks', (tester) async {
      when(() => auth.getWalletAddress()).thenAnswer((_) async => address);
      await pump(tester, const WelcomeBackView());
      await tester.pump();
      expect(find.text('iKryOe...oRjA'), findsOneWidget);
      verify(() =>
              profileNameBloc.add(const LoadProfileNameBeforeLogin(address)))
          .called(1);
    });

    testWidgets('and its ArNS name, once loaded', (tester) async {
      when(() => auth.getWalletAddress()).thenAnswer((_) async => address);
      whenListen(
        profileNameBloc,
        const Stream<ProfileNameState>.empty(),
        initialState: const ProfileNameLoaded(
            PrimaryNameDetails(primaryName: 'arie'), address),
      );
      await pump(tester, const WelcomeBackView());
      await tester.pump();
      expect(find.text('arie'), findsOneWidget);
      expect(find.text('iKryOe...oRjA'), findsOneWidget);
    });

    testWidgets('says the password is being checked, then that it was wrong',
        (tester) async {
      whenListen(
        loginBloc,
        Stream<LoginState>.fromIterable(
            [LoginCheckingPassword(), LoginPasswordFailed()]),
        initialState: const PromptPassword(alreadyLoggedIn: true),
      );
      await pump(tester, const WelcomeBackView());
      expect(find.text('Invalid password. Please try again.'), findsOneWidget);

      await tester.enterText(find.byType(EditableText), 'again');
      await tester.pump();
      expect(find.text('Invalid password. Please try again.'), findsNothing,
          reason: 'typing again clears it');
    });

    testWidgets('shows that it is checking', (tester) async {
      whenListen(loginBloc, const Stream<LoginState>.empty(),
          initialState: LoginCheckingPassword());
      await pump(tester, const WelcomeBackView());
      expect(find.text('Checking your password...'), findsOneWidget);
    });

    testWidgets(
        'Use a different account forgets this one after asking, '
        'and keeps the page', (tester) async {
      await pump(tester, const WelcomeBackView());
      await tester.tap(find.byKey(const Key('welcomeBackDifferentAccount')));
      await tester.pumpAndSettle();
      expect(find.text('Forget wallet'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(added().single, isA<ForgetWallet>());
      expect(find.byType(WelcomeBackView), findsOneWidget,
          reason: 'only the dialog closes; the bloc moves the panel on');
    });
  });
}
