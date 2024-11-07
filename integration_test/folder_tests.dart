import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';
import 'login_tests.dart';

Future<void> testCreateFolderFromEmptyPage(WidgetTester tester) async {
  await I.see.button('Create Folder').tap().wait(100).go(tester);
  await I.see
      .textField('folderNameTextField')
      .enterText('Test Folder')
      .go(tester);
  await I.see.button('CREATE').tap().wait(5000).go(tester);
  I.see.page(driveDetailPageKey);
  I.see.text('Test Folder');
}

Future<void> testCreatePublicFolderFromDriveDetailPage(
    WidgetTester tester) async {
  await I.see.newButton().tap().wait(100).go(tester);
  await I.see.button('New Folder').tap().wait(1000).go(tester);
  await I.see
      .textField('folderNameTextField')
      .enterText('Test Folder')
      .go(tester);
  await I.see.button('CREATE').tap().wait(1000).go(tester);
  await I.wait(5000);
  I.see.text('Test Folder');
}

void main() {
  group('Folder Tests - Logged In Users', () {
    testWidgets('Create public folder from drive detail page', (tester) async {
      await initApp(tester, deleteDatabase: true);
      await testLoginSuccess(tester);
      await I.wait(10000);
      await testCreatePublicFolderFromDriveDetailPage(tester);
    });
  });
}
