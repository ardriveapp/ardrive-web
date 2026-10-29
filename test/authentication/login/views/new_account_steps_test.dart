import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/login_page.dart';
import 'package:ardrive/authentication/login/views/modals/secure_your_wallet_modal.dart';
import 'package:ardrive/authentication/login/views/recovery_phrase_view.dart';
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

  group('choose a password, new account', () {
    Widget dialog({bool isNewUser = true}) => SecureYourWalletWidget(
          loginBloc: loginBloc,
          wallet: getTestWallet(),
          mnemonic: _mnemonic,
          isNewUser: isNewUser,
          showWalletCreated: true,
        );

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
}
