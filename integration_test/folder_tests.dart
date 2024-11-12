import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';
import 'login_tests.dart';

Future<void> testCreateFolderFromEmptyPage(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Create Folder').tap().wait(100).go();
  await i.see.textField('folderNameTextField').enterText('Test Folder').go();
  await i.see.button('CREATE').tap().wait(5000).go();
  i.see.page(driveDetailPageKey);
  i.see.text('Test Folder');
}

Future<void> testCreatePublicFolderFromDriveDetailPage(
    WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.newButton().tap().wait(100).go();
  await i.see.button('New Folder').tap().wait(1000).go();
  await i.see.textField('folderNameTextField').enterText('Test Folder').go();
  await i.see.button('CREATE').tap().wait(1000).go();
  await i.wait(5000);
  i.see.text('Test Folder');
}

void main() {
  group('Folder Tests - Logged In Users', () {
    testWidgets('Create public folder from drive detail page', (tester) async {
      final i = I(see: See(tester: tester));

      await initApp(tester, deleteDatabase: true);
      await testLoginSuccess(tester);
      await i.wait(10000);
      await testCreatePublicFolderFromDriveDetailPage(tester);
    });
  });
}
