// ignore_for_file: non_constant_identifier_names

import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  group('Logout Tests', () {
    testWidgets('User can log out successfully', (WidgetTester tester) async {
      await runPreConditionUserLoggedIn(tester);
      await testLogoutSuccess(tester);
    });
  });
}

Future<void> testLogoutSuccess(WidgetTester tester) async {
  I.see.page(driveDetailPageKey).wait(10000);
  await I.see.profileCard().tap().wait(5000).go(tester);
  await I.wait(1000);
  await I.see.button('Log out').tap().wait(1000).go(tester);    
  I.see.button('Log In');
}
