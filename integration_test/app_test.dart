import 'package:ardrive/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // group('end-to-end test', () {
  testWidgets('build and run', (tester) async {
    await initializeServices();

    await tester.pumpWidget(const App());

    for (int i = 0; i < 3; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final signUpButton = find.text('Sign Up');

    await tester.tap(signUpButton);

    for (int i = 0; i < 1; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final createAWalletButton = find.text('Create a Wallet');

    await tester.tap(createAWalletButton);

    for (int i = 0; i < 20; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final ardriveTextFieldPassword = find.byKey(const Key('password'));
    final ardriveTextFieldConfirmPassword =
        find.byKey(const Key('confirmPassword'));

    await tester.enterText(ardriveTextFieldPassword, '12345678');
    await tester.enterText(ardriveTextFieldConfirmPassword, '12345678');

    final continueButton = find.text('Continue');

    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(continueButton);

    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final nextButton = find.text('Next');

    await tester.tap(nextButton);

    for (int i = 0; i < 5; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final nextButton2 = find.text('Next');

    await tester.tap(nextButton2);

    for (int i = 0; i < 5; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final getYourWallet = find.text('Get your wallet');

    await tester.tap(getYourWallet);

    for (int i = 0; i < 5; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final copyWalletButton = find.text('Copy Seed Phrase');

    await tester.tap(copyWalletButton);

    for (int i = 0; i < 3; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final downloadKeyFile = find.text('Download Keyfile');

    await tester.tap(downloadKeyFile);

    for (int i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    final checkbox = find.byType(Checkbox);

    await tester.tap(checkbox);

    for (int i = 0; i < 2; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    final goToApp = find.text('Go to App');

    await tester.tap(goToApp);

    for (int i = 0; i < 10; i++) {
      await tester.pump(Duration(seconds: 1));
    }

    // sleep(const Duration(seconds: 10));

    // return TestAsyncUtils.guard(() async {
    //   logger.d('Initializing services');

    // await initializeServices();

    //   logger.d('App loaded');

    // await tester.pumpWidget(const App());
    // });

    // // Verify the counter starts at 0.
    // expect(find.text('0'), findsOneWidget);

    // // Finds the floating action button to tap on.
    // final fab = find.byKey(const ValueKey('increment'));

    // // Emulate a tap on the floating action button.
    // await tester.tap(fab);

    // // Trigger a frame.
    // await tester.pumpAndSettle();

    // // Verify the counter increments by 1.
    // expect(find.text('1'), findsOneWidget);
  });
  // });
}
