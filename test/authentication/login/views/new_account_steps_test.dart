import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/creating_account_view.dart';
import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/authentication/password/new_password_fields.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/authentication/login/views/modals/secure_your_wallet_modal.dart';
import 'package:ardrive/authentication/login/views/recovery_phrase_view.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      String? sourceWalletAddress,
    }) =>
        SecureYourWalletWidget(
          loginBloc: loginBloc,
          wallet: getTestWallet(),
          mnemonic: mnemonic,
          sourceWalletAddress: sourceWalletAddress,
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

    testWidgets(
        'says plainly it can\'t be recovered, and that the recovery phrase '
        'alone doesn\'t open private files', (tester) async {
      await pump(tester, dialog());
      expect(
          find.text('It locks your private files. ArDrive can\'t recover it, '
              'so keep it somewhere safe.'),
          findsOneWidget);
      expect(
          find.text(
              'Your recovery phrase doesn\'t open private files without it.'),
          findsOneWidget);
    });

    testWidgets('says nothing of a recovery phrase to an account without one',
        (tester) async {
      await pump(tester, dialog(fromSignUp: true, mnemonic: null));
      expect(find.byKey(const Key('newPasswordRecoveryNote')), findsNothing);
    });

    group('on a phone', () {
      /// The modal as the app shows it, a dialog route, with a suggestion
      /// filled in. Returns its scroll view.
      Future<ScrollableState> openSuggested(
          WidgetTester tester, Size size, Widget modal) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ArDriveApp(
            builder: (context) => MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              // Above the navigator, as in the app: the dialog is a route.
              builder: (context, child) => MultiBlocProvider(
                providers: [
                  BlocProvider<LoginBloc>.value(value: loginBloc),
                  BlocProvider<ProfileNameBloc>.value(value: profileNameBloc),
                ],
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showAnimatedDialog(context,
                        content: modal, useRootNavigator: false),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final suggest = find.byKey(const Key('suggestPasswordButton'));
        await tester.ensureVisible(suggest);
        await tester.pumpAndSettle();
        await tester.tap(suggest);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'nothing overflows');
        return tester.state<ScrollableState>(find
            .descendant(
                of: find.byType(SecureYourWalletWidget),
                matching: find.byType(Scrollable))
            .first);
      }

      /// Continue can be reached, by scrolling if need be, wholly on screen.
      Future<void> expectContinueReachable(
          WidgetTester tester, ScrollableState scroll, Size size) async {
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        final button =
            tester.getRect(find.widgetWithText(ArDriveButtonNew, 'Continue'));
        expect(button.top, greaterThanOrEqualTo(0));
        expect(button.bottom, lessThanOrEqualTo(size.height));
        expect(tester.takeException(), isNull);
      }

      testWidgets('fits 390 by 844, Continue showing without a scroll',
          (tester) async {
        const size = Size(390, 844);
        final scroll = await openSuggested(tester, size, dialog());
        expect(scroll.position.maxScrollExtent, 0,
            reason: 'the modal must fit, not scroll');
        expect(
            tester
                .getRect(find.widgetWithText(ArDriveButtonNew, 'Continue'))
                .bottom,
            lessThanOrEqualTo(size.height));
      });

      // The test font is taller than the app's, so these are held to
      // "reachable, nothing clipped" rather than "no scroll at all".
      final variants = <String, Widget Function()>{
        'a retry': () => dialog(retrying: true),
        'a wallet card': () => dialog(
            fromSignUp: true,
            mnemonic: null,
            sourceWalletAddress: 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG'),
      };
      for (final variant in variants.entries) {
        testWidgets('with ${variant.key}, 390 by 844, Continue is reachable',
            (tester) async {
          const size = Size(390, 844);
          final scroll = await openSuggested(tester, size, variant.value());
          await expectContinueReachable(tester, scroll, size);
        });
      }

      testWidgets('375 by 667 scrolls to Continue, nothing clipped',
          (tester) async {
        const size = Size(375, 667);
        final scroll = await openSuggested(tester, size, dialog());
        await expectContinueReachable(tester, scroll, size);
      });
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
      expect(find.text('Suggest another'), findsOneWidget);
      // The intro says it once; the suggestion doesn't say it again.
      expect(find.textContaining("ArDrive can't recover it"), findsOneWidget);
      expect(continueEnabled(tester), isTrue);
    });

    group('a suggestion, masked, with one eye for both fields', () {
      bool obscured(WidgetTester tester, String key) => tester
          .widget<EditableText>(find.descendant(
              of: find.byKey(Key(key)), matching: find.byType(EditableText)))
          .obscureText;
      String text(WidgetTester tester, String key) => tester
          .widget<EditableText>(find.descendant(
              of: find.byKey(Key(key)), matching: find.byType(EditableText)))
          .controller
          .text;

      Future<void> suggest(WidgetTester tester) async {
        await tester.tap(find.byKey(const Key('suggestPasswordButton')));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();
      }

      /// The clipboard, which takes the text unless told to refuse, as a
      /// phone's browser can.
      List<String> clipboard(WidgetTester tester, {bool refuses = false}) {
        final copied = <String>[];
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            if (refuses) {
              throw PlatformException(code: 'denied');
            }
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        addTearDown(() => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null));
        return copied;
      }

      testWidgets(
          'fills both fields masked; the eye shows and hides both; the card '
          'never shows it', (tester) async {
        await pump(tester, dialog());
        expect(obscured(tester, 'signUpPassword'), isTrue);

        await suggest(tester);
        final phrase = text(tester, 'signUpPassword');
        expect(phrase, isNotEmpty);
        expect(text(tester, 'signUpConfirmPassword'), phrase);
        expect(obscured(tester, 'signUpPassword'), isTrue);
        expect(obscured(tester, 'signUpConfirmPassword'), isTrue);
        expect(
            find.descendant(
                of: find.byKey(const Key('suggestedPassphrase')),
                matching: find.text(phrase)),
            findsNothing);

        await tester.tap(find.byKey(const Key('signUpPasswordReveal')));
        await tester.pump();
        expect(obscured(tester, 'signUpPassword'), isFalse);
        expect(obscured(tester, 'signUpConfirmPassword'), isFalse);

        await tester.tap(find.byKey(const Key('signUpPasswordReveal')));
        await tester.pump();
        expect(obscured(tester, 'signUpPassword'), isTrue);
        expect(obscured(tester, 'signUpConfirmPassword'), isTrue);

        // Another suggestion stays masked too.
        await tester.tap(find.text('Suggest another'));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();
        expect(obscured(tester, 'signUpPassword'), isTrue);
        expect(obscured(tester, 'signUpConfirmPassword'), isTrue);
      });

      testWidgets('Copy copies it, masked, and says so', (tester) async {
        final copied = clipboard(tester);
        await pump(tester, dialog());
        await suggest(tester);
        final phrase = text(tester, 'signUpPassword');

        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(copied, [phrase]);
        expect(find.text('Copied!'), findsOneWidget);
        expect(find.text("Couldn't copy"), findsNothing);

        // In the links row, at its end, clear of the meter above.
        final message = tester
            .getRect(find.byKey(const Key('suggestedPassphraseCopyMessage')));
        final row =
            tester.getRect(find.byKey(const Key('suggestedPassphrase')));
        final meter = tester.getRect(find.byType(PasswordStrengthMeter));
        expect(message.top, greaterThanOrEqualTo(row.top));
        expect(message.bottom, lessThanOrEqualTo(row.bottom));
        expect(message.right, moreOrLessEquals(row.right, epsilon: 0.5));
        expect(message.overlaps(meter), isFalse);
        expect(
            tester.widget<Text>(find.text('Copied!')).style?.color,
            ArDriveTheme.of(tester.element(find.text('Copied!')))
                .themeData
                .colorTokens
                .statusSuccessFg);

        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text('Copied!'), findsNothing);
      });

      testWidgets('Copy refused by the browser says so, never Copied',
          (tester) async {
        final copied = clipboard(tester, refuses: true);
        await pump(tester, dialog());
        await suggest(tester);

        await tester.tap(find.text('Copy'));
        await tester.pump();
        expect(copied, isEmpty);
        expect(find.text("Couldn't copy"), findsOneWidget);
        expect(find.text('Copied!'), findsNothing);
        expect(
            tester.widget<Text>(find.text("Couldn't copy")).style?.color,
            ArDriveTheme.of(tester.element(find.text("Couldn't copy")))
                .themeData
                .colorTokens
                .statusErrorFg);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(find.text("Couldn't copy"), findsNothing);
      });

      testWidgets('leaves the caret after it, nothing selected',
          (tester) async {
        await pump(tester, dialog());
        await suggest(tester);
        for (final key in ['signUpPassword', 'signUpConfirmPassword']) {
          final controller = tester
              .widget<EditableText>(find.descendant(
                  of: find.byKey(Key(key)),
                  matching: find.byType(EditableText)))
              .controller;
          expect(controller.selection,
              TextSelection.collapsed(offset: controller.text.length),
              reason: key);
        }
      });

      testWidgets('Suggest another keeps the fields shown when shown',
          (tester) async {
        await pump(tester, dialog());
        await suggest(tester);
        await tester.tap(find.byKey(const Key('signUpPasswordReveal')));
        await tester.pump();
        final first = text(tester, 'signUpPassword');

        await tester.tap(find.text('Suggest another'));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 300)));
        await tester.pumpAndSettle();
        expect(text(tester, 'signUpPassword'), isNot(first));
        expect(obscured(tester, 'signUpPassword'), isFalse);
        expect(obscured(tester, 'signUpConfirmPassword'), isFalse);
      });

      testWidgets(
          'a password changed after a suggestion no longer matches the '
          'confirmation: Continue goes off and the field says so',
          (tester) async {
        await pump(tester, dialog());
        await suggest(tester);
        expect(continueEnabled(tester), isTrue);

        await tester.enterText(
            find.descendant(
                of: find.byKey(const Key('signUpPassword')),
                matching: find.byType(EditableText)),
            'Copper meadow 92 kites unfold');
        await tester.pump();

        expect(continueEnabled(tester), isFalse);
        expect(find.text('The confirmation password does not match.'),
            findsOneWidget);

        await tester.enterText(
            find.descendant(
                of: find.byKey(const Key('signUpConfirmPassword')),
                matching: find.byType(EditableText)),
            'Copper meadow 92 kites unfold');
        await tester.pump();
        expect(continueEnabled(tester), isTrue);
        expect(find.text('The confirmation password does not match.'),
            findsNothing);
      });

      testWidgets('typing a password of one\'s own drops the suggestion',
          (tester) async {
        await pump(tester, dialog());
        await suggest(tester);

        await tester.enterText(
            find.descendant(
                of: find.byKey(const Key('signUpPassword')),
                matching: find.byType(EditableText)),
            'Copper meadow 92 kites unfold');
        await tester.pump();

        expect(obscured(tester, 'signUpPassword'), isTrue);
        expect(obscured(tester, 'signUpConfirmPassword'), isTrue);
        expect(find.byKey(const Key('suggestedPassphrase')), findsNothing);
      });

      testWidgets('the text stops short of the eye', (tester) async {
        await pump(tester, dialog());
        await tester.tap(find.byKey(const Key('signUpPasswordReveal')));
        await tester.enterText(
            find.descendant(
                of: find.byKey(const Key('signUpPassword')),
                matching: find.byType(EditableText)),
            'harbor coast ' * 8);
        await tester.pump();

        final input = tester.getRect(find.descendant(
            of: find.byKey(const Key('signUpPassword')),
            matching: find.byType(EditableText)));
        final eye =
            tester.getRect(find.byKey(const Key('signUpPasswordReveal')));
        expect(eye.left - input.right, greaterThanOrEqualTo(ArDriveSpacing.xs));
      });
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
