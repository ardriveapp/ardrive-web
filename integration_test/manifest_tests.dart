import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';
import 'login_tests.dart';

/// Pre-condition: User must be logged in
Future<void> testManifestCreation(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.newButton().tap().wait(100).go();
  await i.see.button('Advanced').tap().wait(100).go();
  await i.see.button('New Manifest').tap().wait(100).go();
  await i.see.textField('manifestName').enterText('new_manifest').go();
  await i.wait(500);
  await i.see.button('NEXT').tap().wait(100).go();
  await i.see.button('CREATE HERE').tap().wait(100).go();
  await i.wait(5000);
  i.see.text('new_manifest');
  await i.see.button('CONFIRM').tap().wait(5000).go();
  await i.see.button('Close').tap().wait(100).go();
  i.see.page('driveDetailPage');
  i.see.text('new_manifest');
}

void main() {
  group('Manifest Tests - Logged In Users', () {
    testWidgets('Test manifest creation', (tester) async {
      final i = I(see: See(tester: tester));

      await initApp(tester, deleteDatabase: true);
      await testLoginSuccess(tester);
      await i.wait(10000);
      await testManifestCreation(tester);
    });
  });
}
