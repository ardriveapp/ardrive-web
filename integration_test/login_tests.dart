// ignore_for_file: non_constant_identifier_names

import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('Login Tests', () {
    testWidgets('User can log in successfully', (WidgetTester tester) async {
     await initApp(tester, deleteDatabase: true);
     await testLoginSuccess(tester);
    });
  });
}    //testWidgets('User can unlock their account', (WidgetTester tester) async {
    //   await initApp(tester);
    //   await unlockUser(tester);
    // });

    // testWidgets('Login fails with incorrect credentials',
    //     (WidgetTester tester) async {
    //   await initApp(tester, deleteDatabase: true);
    //   await testLoginFailure(tester);
    //   await tester.pumpAndSettle();
    // });

    // testWidgets('User can log in with seed phrase', (WidgetTester tester) async {
    //   await initApp(tester, deleteDatabase: true);
    //   await testLoginSeedPhrase(tester);
    //   });


Future<void> testLoginSuccess(WidgetTester tester) async {
  await I.see.button('Log In').tap().wait(500).go(tester);
  await I.see.button('Import Wallet').tap().wait(500).go(tester);
  I.see.multipleText('Import Wallet', 2);
  await I.pickFileTestWallet(tester);
  I.see.button('Continue');
  await I.see.button('Use Keyfile').tap().wait(5000).go(tester);
  await I.see.textField('password-input').enterText('123').go(tester);
  await I.wait(100);
  await I.see.button('Continue').tap().wait(5000).go(tester);
  await I.waitToSee(driveDetailPageKey, tester, 30);
  I.see.page(driveDetailPageKey).wait(10000);
}

Future<void> testLoginFailure(WidgetTester tester) async {
  await I.see.button('Log In').tap().wait(100).go(tester);
  await I.see.button('Import Wallet').tap().wait(1000).go(tester);
  await I.pickFileTestWallet(tester);
  await I.see.button('Use Keyfile').tap().wait(3000).go(tester);
  await I.see
      .textField('password-input')
      .enterText('WRONG_PASSWORD')
      .wait(500)
      .go(tester);
  await I.see.button('Continue').tap().wait(5000).go(tester);
  I.see.text('Invalid password. Please try again.');
}

Future<void> unlockUser(WidgetTester tester) async {
  I.see.text('Enter Your Password');
  await I.see.textField('password-input').enterText('123').wait(500).go(tester);
  await I.see.button('Continue').tap().wait(5000).go(tester);
  await I.waitToSee(driveDetailPageKey, tester, 30);
  I.see.page(driveDetailPageKey);
}

Future<void> testLoginSeedPhrase(WidgetTester tester) async {
  await I.see.button('Log In').tap().wait(100).go(tester);
  await I.see.button('Import Wallet').tap().wait(1000).go(tester);
  await I.see
      .textField('import_wallet_modal_seed_phrase_text_field')
      .enterText(
          'measure brown citizen laptop dawn marriage twin tower taste rent long canvas')
      .go(tester);
  await I.see.button('Continue').tap().wait(30000).wait(1000).go(tester);
  await I.see.textField('password-input').enterText('123').wait(1000).go(tester);
  await I.see.button('Continue').tap().wait(3000).go(tester);
  await I.waitToSee(driveDetailPageKey, tester, 1000);
  I.see.page(driveDetailPageKey);
}