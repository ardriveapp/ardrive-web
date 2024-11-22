import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

void main() {
  group('Logout Tests', () {
    testWidgets('User can log out successfully', (WidgetTester tester) async {
      final i = I(see: See(tester: tester));

      await runPreConditionUserLoggedInMobile(tester);
      await i.wait(5000);
      await testLogoutSuccess(tester);
    });
  });
}

Future<void> testLogoutSuccess(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  i.see.page(driveDetailPageKey).wait(10000);
  await i.see.profileCard().tap().wait(5000).go();
  await i.wait(1000);
  await i.see.button('Log out').tap().wait(5000).go();
  i.see.button('Log In');
  await tester.pumpAndSettle();
}
