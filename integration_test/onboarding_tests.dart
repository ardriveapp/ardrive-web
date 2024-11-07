import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';

Future<void> testSignUpAndOnboarding(WidgetTester tester) async {
  await I.see.button('Sign Up').tap().wait(1000).go(tester);
  await I.see.button('Create a Wallet').tap().go(tester);
  await I.waitToSee('password', tester, 50);
  await I.see.textField('password').enterText('12345678').go(tester);
  await I.see.textField('confirmPassword').enterText('12345678').go(tester);
  await I.wait(500);
  await I.see.button('Continue').tap().wait(3000).go(tester);
  await I.see.button('Next').tap().wait(1000).go(tester);
  await I.see.button('Next').tap().wait(1000).go(tester);
  await I.see.button('Get your wallet').tap().wait(1000).go(tester);
  await I.see.button('Download Keyfile').tap().wait(1000).go(tester);
  await I.see.checkbox().tap().wait(1000).go(tester);
  await I.see.button('Go to App').tap().wait(1000).go(tester);
  await I.waitToSee('NoDrivesPage', tester, 30);
  await I.see.page('NoDrivesPage').go(tester);
}

void main() {
  group('Onboarding Tests', () {
    testWidgets('Sign up and onboarding', (tester) async {
      await initApp(tester, deleteDatabase: true);
      await testSignUpAndOnboarding(tester);
    });
  });
}
