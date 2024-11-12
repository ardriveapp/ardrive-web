import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';

Future<void> testSignUpAndOnboarding(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Sign Up').tap().wait(1000).go();
  await i.see.button('Create a Wallet').tap().go();
  await i.waitToSee('password', tester, 50);
  await i.see.textField('password').enterText('12345678').go();
  await i.see.textField('confirmPassword').enterText('12345678').go();
  await i.wait(500);
  await i.see.button('Continue').tap().wait(3000).go();
  await i.see.button('Next').tap().wait(1000).go();
  await i.see.button('Next').tap().wait(1000).go();
  await i.see.button('Get your wallet').tap().wait(1000).go();
  await i.see.button('Download Keyfile').tap().wait(1000).go();
  await i.see.checkbox().tap().wait(1000).go();
  await i.see.button('Go to App').tap().wait(1000).go();
  await i.waitToSee('NoDrivesPage', tester, 30);
  await i.see.page('NoDrivesPage').go();
}

void main() {
  group('Onboarding Tests', () {
    testWidgets('Sign up and onboarding', (tester) async {
      await initApp(tester, deleteDatabase: true);
      await testSignUpAndOnboarding(tester);
    });
  });
}
