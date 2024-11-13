import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';

void main() {
  group('Login Tests', () {
    testWidgets('User can log in successfully', (WidgetTester tester) async {
      await initApp(tester, deleteDatabase: true);
      await testLoginSuccess(tester);
    });

    testWidgets('Login fails with incorrect credentials',
        (WidgetTester tester) async {
      final i = I(see: See(tester: tester));
      await initApp(tester, deleteDatabase: true);
      await i.wait(1000);
      await testLoginFailure(tester);
    });
  });
}

Future<void> testLoginSuccess(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Log In').tap().wait(500).go();

  /// press the backspace key to unfocus the text field
  await tester.sendKeyDownEvent(LogicalKeyboardKey.backspace);
  await i.see.button('Import Wallet').tap().wait(500).go();
  i.see.multipleText('Import Wallet', 2);
  await i.pickFileTestWallet(tester);
  i.see.button('Continue');
  await i.see.button('Use Keyfile').tap().go();
  await i.waitToSee('password-input', tester, 30);
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
