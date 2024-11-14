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
  final i = I(see: See(tester: tester));

  i.see.page(driveDetailPageKey).wait(20000);
  await i.see.profileCard().tap().wait(5000).go();
  await i.wait(1000);
  await i.see.button('Log out').tap().wait(1000).go();
  i.see.button('Log In');
  await tester.pumpAndSettle();
}
