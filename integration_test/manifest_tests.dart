import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';
import 'login_tests.dart';
import 'folder_tests.dart';

/// Pre-condition: User must be logged in
Future<void> testManifestCreation(WidgetTester tester) async {
  await I.see.newButton().tap().wait(100).go(tester);
  await I.see.button('Advanced').tap().wait(100).go(tester);
  await I.see.button('New Manifest').tap().wait(100).go(tester);
  await I.see
      .textField('manifestName')
      .enterText('new_manifest')
      .wait(100)
      .go(tester);
  await I.see.button('NEXT').tap().wait(100).go(tester);
  await I.see.button('CREATE HERE').tap().wait(100).go(tester);
  await I.wait(5000);
  I.see.text('new_manifest');
  await I.see.button('CONFIRM').tap().wait(5000).go(tester);
  await I.see.button('Close').tap().wait(100).go(tester);
  I.see.page('driveDetailPage');
  I.see.text('new_manifest');
}

/// Pre-condition: User must be logged in
/// Pre-condition: Drive must exist
/// Pre-condition: Files must exist
Future<void> testManifestCreationUsingFolder(WidgetTester tester) async {
  await I.see.publicDriveButton('drive test snapshot').tap().wait(5000).go(tester);
  await I.see.button('test-manifest').tap().wait(100).tap().wait(3000).go(tester);
  await I.see.button('test-manifest').tap().wait(100).tap().wait(1000).go(tester);
  await I.see.newButton().tap().wait(1000).go(tester);
  await I.see.button('Advanced').tap().wait(1000).go(tester);
  await I.see.button('New Manifest').tap().wait(1000).go(tester);
  await I.see
      .textField('manifestName')
      .enterText('new_manifest')
      .wait(100)
      .go(tester);
  await I.see.button('NEXT').tap().wait(100).go(tester);
  await I.see.button('CREATE HERE').tap().wait(100).go(tester);
  await I.wait(5000);
  I.see.text('new_manifest');
  await I.see.button('CONFIRM').tap().wait(5000).go(tester);
  await I.see.button('Close').tap().wait(100).go(tester);
  I.see.page('driveDetailPage');
  I.see.text('new_manifest');
}

void main() {
  group('Manifest Tests - Logged In Users', () {
    testWidgets('Test manifest creation', (tester) async {
      await initApp(tester, deleteDatabase: true);
      await testLoginSuccess(tester);
      await I.wait(10000);
      await testManifestCreationUsingFolder(tester);
      await I.wait(10000);
    });
  });
}
