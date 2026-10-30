import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/creating_account_view.dart';
import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/authentication/login/views/modals/secure_your_wallet_modal.dart';
import 'package:ardrive/authentication/login/views/recovery_phrase_view.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/utils.dart';

class _MockLoginBloc extends MockBloc<LoginEvent, LoginState>
    implements LoginBloc {}

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

const _mnemonic =
    'river lantern orbit maple quiet harbor cobalt meadow signal ember canvas summit';

void main() {
  late _MockLoginBloc loginBloc;
  late _MockProfileNameBloc profileNameBloc;

  setUpAll(() {
    registerFallbackValue(const CleanProfileName());
    registerFallbackValue(const CreateNewWallet());
    registerFallbackValue(CreatePassword(
        password: 'p',
        wallet: getTestWallet(),
        isNewUser: true,
        showWalletCreated: true));
  });

  setUp(() {
    loginBloc = _MockLoginBloc();
    profileNameBloc = _MockProfileNameBloc();
    whenListen(loginBloc, const Stream<LoginState>.empty(),
        initialState: const LoginLanding());
    whenListen(profileNameBloc, const Stream<ProfileNameState>.empty(),
        initialState: const ProfileNameInitial(null));
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<LoginBloc>.value(value: loginBloc),
              BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
            ],
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  bool continueEnabled(WidgetTester tester) => !tester
      .widget<ArDriveButtonNew>(
          find.widgetWithText(ArDriveButtonNew, 'Continue'))
      .isDisabled;

  Future<void> enterBoth(WidgetTester tester, String password) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), password);
    await tester.enterText(fields.at(1), password);
    await tester.pump();
  }

  testWidgets('creating an account shows the ArDrive plate stack',
      (tester) async {
    await pump(tester, const CreatingAccountView());

    expect(find.text('Creating your account'), findsOneWidget);
    expect(find.byType(SyncLoadingIndicator), findsOneWidget);
    expect(find.byType(ArDriveLinearProgress), findsNothing);
  });

  group('choose a password, new account', () {
    Widget dialog({
      bool isNewUser = true,
      bool retrying = false,
      String? mnemonic = _mnemonic,
      bool? breached = false,
      bool fromSignUp = false,
    }) =>
        SecureYourWalletWidget(
          loginBloc: loginBloc,
          wallet: getTestWallet(),
          mnemonic: mnemonic,
          isNewUser: isNewUser,
          showWalletCreated: true,
          retrying: retrying,
          fromSignUp: fromSignUp,
          breachCheck: _FakeBreachCheck(breached),
        );

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(ArDriveButtonNew, 'Continue'));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('a password in a known breach is refused', (tester) async {
      await pump(tester, dialog(breached: true));
      await enterBoth(tester, 'my cat likes tuna fish');
      await submit(tester);

      expect(
          find.text('This password has shown up in a data breach. '
              'Choose another.'),
          findsOneWidget);
      verifyNever(() => loginBloc.add(any(that: isA<CreatePassword>())));
    });

    testWidgets('goes ahead when the breach check cannot answer',
        (tester) async {
      await pump(tester, dialog(breached: null));
      await enterBoth(tester, 'my cat likes tuna fish');
      await submit(tester);

      verify(() => loginBloc.add(any(that: isA<CreatePassword>()))).called(1);
    });

    testWidgets('a returning wallet with no drives keeps any password',
        (tester) async {
      // A keyfile, browser wallet or Solana sign-in to a wallet with no
      // drives yet: new to drives, not a new account.
      await pump(tester, dialog(mnemonic: null));
      await enterBoth(tester, 'abc');
      expect(find.byKey(const Key('suggestPasswordButton')), findsNothing);
      expect(continueEnabled(tester), isTrue);
    });

    for (final isNewUser in [true, false]) {
      testWidgets(
          'a wallet chosen from Sign up gets the new-account rules '
          '(${isNewUser ? 'no drives' : 'with public drives'})',
          (tester) async {
        // Wander, Phantom, Solflare or MetaMask chosen from "Create your
        // account": a new ArDrive account, whatever the wallet holds.
        await pump(tester,
            dialog(mnemonic: null, isNewUser: isNewUser, fromSignUp: true));
        expect(find.byKey(const Key('suggestPasswordButton')), findsOneWidget);
        await enterBoth(tester, 'short');
        expect(find.text('Use at least 12 characters.'), findsOneWidget);
        expect(continueEnabled(tester), isFalse);
      });
    }

    testWidgets('says why it is asking again after a failed try',
        (tester) async {
      await pump(tester, dialog());
      expect(find.byKey(const Key('newPasswordRetry')), findsNothing);

      await pump(tester, dialog(retrying: true));
      expect(
          find.textContaining("We couldn't finish setting up"), findsOneWidget);
    });

    testWidgets('says what the password is for, without a wallet card',
        (tester) async {
      await pump(tester, dialog());
      expect(find.text('Choose a password'), findsOneWidget);
      expect(
          find.textContaining('It locks your private files'), findsOneWidget);
      expect(find.text('Forget wallet'), findsNothing);
    });

    testWidgets('a short password is refused', (tester) async {
      await pump(tester, dialog());
      await enterBoth(tester, 'short');
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
    });

    testWidgets('a long but easy one is refused', (tester) async {
      await pump(tester, dialog());
      await enterBoth(tester, 'Summer2024!!');
      expect(find.textContaining('Too easy to guess'), findsOneWidget);
      expect(continueEnabled(tester), isFalse);
    });

    testWidgets('a strong one of their own is accepted', (tester) async {
      await pump(tester, dialog());
      await enterBoth(tester, 'my cat likes tuna fish');
      expect(find.text('Strong'), findsOneWidget);
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('a suggested passphrase fills both fields and shows Copy',
        (tester) async {
      await pump(tester, dialog());
      await tester.tap(find.byKey(const Key('suggestPasswordButton')));
      // The word list loads from the app's assets: real I/O.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('suggestedPassphrase')), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(find.textContaining("ArDrive can't recover it"), findsOneWidget);
      expect(continueEnabled(tester), isTrue);
    });

    testWidgets('a returning user keeps any password', (tester) async {
      await pump(tester, dialog(isNewUser: false));
      await enterBoth(tester, 'abc');
      expect(find.byKey(const Key('suggestPasswordButton')), findsNothing);
      expect(continueEnabled(tester), isTrue);
    });
  });

  group('save your recovery phrase', () {
    for (final saved in [true, false]) {
      testWidgets(
          'a keyfile ${saved ? 'saved' : 'not saved'} '
          '${saved ? 'lets them' : 'does not let them'} continue',
          (tester) async {
        await pump(
          tester,
          RecoveryPhraseView(
            mnemonic: _mnemonic,
            wallet: getTestWallet(),
            saveKeyfile: (_) async => saved,
          ),
        );
        await tester.tap(find.text('Download a keyfile instead'));
        await tester.pump();

        final button = tester.widget<ArDriveButtonNew>(
            find.byKey(const Key('recoveryContinue')));
        expect(button.isDisabled, !saved);
        // The phrase box is about the phrase, and stays as it was.
        expect(
            tester
                .widget<ArDriveCheckBox>(find.byKey(const Key('recoverySaved')))
                .checked,
            isFalse);
      });
    }

    test('stays on screen once the password is set', () {
      // The bloc reports the phrase, then that the password was created.
      expect(
          loginPanelRebuildsOn(LoginDownloadGeneratedWallet(
              wallet: getTestWallet(), mnemonic: _mnemonic)),
          isTrue);
      expect(loginPanelRebuildsOn(LoginCreatePasswordComplete()), isFalse);
    });

    testWidgets('the words are hidden until shown', (tester) async {
      await pump(tester,
          RecoveryPhraseView(mnemonic: _mnemonic, wallet: getTestWallet()));
      ImageFiltered words() =>
          tester.widget<ImageFiltered>(find.byKey(const Key('recoveryWords')));
      expect(words().enabled, isTrue);
      await tester.tap(find.byKey(const Key('recoveryShow')));
      await tester.pump();
      expect(words().enabled, isFalse);
    });

    testWidgets('Continue waits for the saved box, then finishes',
        (tester) async {
      await pump(tester,
          RecoveryPhraseView(mnemonic: _mnemonic, wallet: getTestWallet()));
      bool disabled() => tester
          .widget<ArDriveButtonNew>(find.byKey(const Key('recoveryContinue')))
          .isDisabled;
      expect(disabled(), isTrue);
      await tester.tap(find.text("I've saved my recovery phrase"));
      await tester.pump();
      expect(disabled(), isFalse);
      await tester.tap(find.byKey(const Key('recoveryContinue')));
      verify(() => loginBloc.add(any(that: isA<FinishOnboarding>()))).called(1);
    });
  });

  // Closing a sign-up's password step, or "Use a different wallet", must
  // never forget an account already stored here: a returning user who
  // wandered into Sign up lost their own account to this close.
  group('leaving the wallet from Choose a password', () {
    Future<void> pumpAsRoute(WidgetTester tester, Widget dialog) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 1600);
      addTearDown(tester.view.reset);
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            navigatorKey: navigator,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MultiBlocProvider(
              providers: [
                BlocProvider<LoginBloc>.value(value: loginBloc),
                BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
              ],
              child: child!,
            ),
            home: const Scaffold(body: Text('Landing')),
          ),
        ),
      );
      navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(body: Center(child: dialog))));
      await tester.pumpAndSettle();
    }

    List<LoginEvent> added() =>
        verify(() => loginBloc.add(captureAny())).captured.cast<LoginEvent>();

    testWidgets('closing a new account forgets nothing stored here',
        (tester) async {
      final wallet = getTestWallet();
      await pumpAsRoute(
        tester,
        SecureYourWalletWidget(
          loginBloc: loginBloc,
          wallet: wallet,
          mnemonic: _mnemonic,
          isNewUser: true,
          showWalletCreated: true,
          // As the bloc emits it for a generated wallet: no fromSignUp.
          breachCheck: _FakeBreachCheck(false),
        ),
      );
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(added().single, const LeaveWallet(),
          reason: 'ForgetWallet signed out whatever account was stored; '
              'a sign-up goes back to the first panel, as it always did');
      expect(find.byType(SecureYourWalletWidget), findsNothing);
    });

    testWidgets(
        'a wallet that has used ArDrive offers "Use a different wallet", '
        'not a round X', (tester) async {
      final wallet = getTestWallet();
      await pumpAsRoute(
        tester,
        SecureYourWalletWidget(
          loginBloc: loginBloc,
          wallet: wallet,
          isNewUser: false,
          showWalletCreated: false,
          breachCheck: _FakeBreachCheck(false),
        ),
      );
      expect(find.byTooltip('Forget wallet'), findsNothing);
      await tester.tap(find.byKey(const Key('useDifferentWallet')));
      await tester.pumpAndSettle();

      expect(added().single, const LeaveWallet(),
          reason: 'back to the first panel, as leaving always went');
    });
  });
}

class _FakeBreachCheck implements BreachedPasswordCheck {
  _FakeBreachCheck(this.answer);

  final bool? answer;

  @override
  Duration get timeout => Duration.zero;

  @override
  Future<bool?> isBreached(String password) async => answer;
}
