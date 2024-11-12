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

    testWidgets('User can unlock their account', (WidgetTester tester) async {
      await initApp(tester);
      await unlockUser(tester);
    });

    testWidgets('Login fails with incorrect credentials',
        (WidgetTester tester) async {
      await initApp(tester, deleteDatabase: true);
      await testLoginFailure(tester);
      await tester.pumpAndSettle();
    });

    testWidgets('User can log in with seed phrase',
        (WidgetTester tester) async {
      await initApp(tester, deleteDatabase: true);
      await testLoginSeedPhrase(tester);
    });
  });
}

Future<void> testLoginSuccess(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Log In').tap().wait(500).go();
  await i.see.button('Import Wallet').tap().wait(500).go();
  i.see.multipleText('Import Wallet', 2);
  await i.pickFileTestWallet(tester);
  i.see.button('Continue');
  await i.see.button('Use Keyfile').tap().wait(5000).go();
  await i.see.textField('password-input').enterText('123').go();
  await i.wait(100);
  await i.see.button('Continue').tap().wait(5000).go();
  await i.waitToSee(driveDetailPageKey, tester, 30);
  i.see.page(driveDetailPageKey).wait(10000);
}

Future<void> testLoginFailure(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Log In').tap().wait(100).go();
  await i.see.button('Import Wallet').tap().wait(1000).go();
  await i.pickFileTestWallet(tester);
  await i.see.button('Use Keyfile').tap().wait(3000).go();
  await i.see
      .textField('password-input')
      .enterText('WRONG_PASSWORD')
      .wait(500)
      .go();
  await i.see.button('Continue').tap().wait(5000).go();
  i.see.text('Invalid password. Please try again.');
}

Future<void> unlockUser(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  i.see.text('Enter Your Password');
  await i.see.textField('password-input').enterText('123').wait(500).go();
  await i.see.button('Continue').tap().wait(5000).go();
  await i.waitToSee(driveDetailPageKey, tester, 30);
  i.see.page(driveDetailPageKey);
}

Future<void> testLoginSeedPhrase(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Log In').tap().wait(100).go();
  await i.see.button('Import Wallet').tap().wait(1000).go();
  await i.see
      .textField('import_wallet_modal_seed_phrase_text_field')
      .enterText(
          'measure brown citizen laptop dawn marriage twin tower taste rent long canvas')
      .go();
  await i.see.button('Continue').tap().wait(30000).wait(1000).go();
  await i.see.textField('password-input').enterText('123').wait(1000).go();
  await i.see.button('Continue').tap().wait(3000).go();
  await i.waitToSee(driveDetailPageKey, tester, 1000);
  i.see.page(driveDetailPageKey);
}
