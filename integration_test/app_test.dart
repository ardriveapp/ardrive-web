import 'package:ardrive/main.dart';
import 'package:ardrive/pages/no_drives/no_drives_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('OnBoarding Flow', () {
    testWidgets(
        'should complete the onboarding flow successfully creating a new wallet',
        (tester) async {
      /// Initialize services
      ///
      /// Always call this before running tests
      await initializeServices();

      /// Pump the widget
      await tester.pumpWidget(const App(
        runningFromFlutterTest: true,
      ));

      /// Wait for the app to load
      await _waitAndUpdate(tester, 1);

      /// Find the sign up button and tap it
      final signUpButton = find.text('Sign Up');
      expect(signUpButton, findsOneWidget);
      await tester.tap(signUpButton);

      /// Wait for the next page to load
      await _waitAndUpdate(tester, 1);

      /// Find the create a wallet button and tap it
      final createAWalletButton = find.text('Create a Wallet');
      expect(createAWalletButton, findsOneWidget);

      /// Tap the create a wallet button
      await tester.tap(createAWalletButton);

      /// Wait for the wallet creation page to load
      await _waitAndUpdate(tester, 100, breakCondition: () {
        try {
          final passwordField = find.byKey(const Key('password'));
          expect(passwordField, findsOneWidget);
          return true;
        } catch (e) {
          return false;
        }
      });

      /// Find the password and confirm password fields and enter the password
      final ardriveTextFieldPassword = find.byKey(const Key('password'));
      final ardriveTextFieldConfirmPassword =
          find.byKey(const Key('confirmPassword'));

      /// Check if the password and confirm password fields are found
      expect(ardriveTextFieldPassword, findsOneWidget);
      expect(ardriveTextFieldConfirmPassword, findsOneWidget);

      await _waitAndUpdate(tester, 1);

      /// Enter the password and confirm password
      await tester.enterText(ardriveTextFieldPassword, '12345678');

      await _waitAndUpdate(tester, 1);

      await tester.enterText(ardriveTextFieldConfirmPassword, '12345678');

      await _waitAndUpdate(tester, 1);

      /// Find the continue button and tap it
      final continueButton = find.text('Continue');
      expect(continueButton, findsOneWidget);

      await _waitAndUpdate(tester, 1);

      /// Tap the continue button
      await tester.tap(continueButton);

      /// Wait for the next page to load
      await _waitAndUpdate(tester, 3);

      /// On Boarding Pages
      /// Page 1
      /// Find the next button and tap it
      final nextButton = find.text('Next');

      await tester.tap(nextButton);

      await _waitAndUpdate(tester, 1);

      /// Page 2

      final nextButton2 = find.text('Next');

      await tester.tap(nextButton2);

      await _waitAndUpdate(tester, 1);

      /// Page 3 - last one
      final getYourWallet = find.text('Get your wallet');

      expect(getYourWallet, findsOneWidget);

      /// Tap the get your wallet button
      await tester.tap(getYourWallet);

      await _waitAndUpdate(tester, 1);

      /// Download Keyfile Page
      ///
      /// Find the download keyfile button and tap it
      final downloadKeyFile = find.text('Download Keyfile');
      expect(downloadKeyFile, findsOneWidget);
      await tester.tap(downloadKeyFile);

      await _waitAndUpdate(tester, 1);

      /// Find the checkbox and tap it
      final checkbox = find.byType(Checkbox);
      expect(checkbox, findsOneWidget);

      await tester.tap(checkbox);

      await _waitAndUpdate(tester, 1);

      /// The Go to App button should be enabled
      final goToApp = find.text('Go to App');
      expect(goToApp, findsOneWidget);

      /// Tap the go to app button
      await tester.tap(goToApp);
      await _waitAndUpdate(tester, 1);

      final driveExplorerEmptyState = find.byType(NoDrivesPage);
      expect(driveExplorerEmptyState, findsOneWidget);

      /// finish the test
      await tester.pumpAndSettle();
    });
  });
}

Future<void> _waitAndUpdate(WidgetTester tester, int seconds,
    {bool Function()? breakCondition}) async {
  for (int i = 0; i < seconds; i++) {
    for (int j = 0; j < 10; j++) {
      if (breakCondition != null) {
        if (breakCondition()) {
          return;
        }
      }

      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}