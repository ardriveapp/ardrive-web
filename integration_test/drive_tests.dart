import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

Future<void> testCreateDriveFromEmptyPage(WidgetTester tester) async {
  await I.see.button('Create new public drive').tap().wait(100).go(tester);
  await I.see
      .textField('driveNameTextField')
      .enterText('Test Drive')
      .go(tester);
  await I.see.button('CREATE').tap().wait(5000).go(tester);
  I.see.page('driveDetailPage');
  I.see.multipleText('Test Drive', 2);
}

/// Pre-condition: User must be logged in
Future<void> testCreatePublicDriveFromNewButton(WidgetTester tester) async {
  await I.see.newButton().tap().wait(1000).go(tester);
  await I.see.button('New Drive').tap().wait(1000).go(tester);
  await I.see
      .textField(driveNameTextFieldKey)
      .enterText('Test Drive - Integration Test')
      .go(tester);
  await I.see.buttonByKey(drivePrivateButtonKey).tap().wait(500).go(tester);
  await I.see.buttonByKey(drivePublicButtonKey).tap().wait(500).go(tester);
  await I.see.buttonByKey(createDriveButtonKey).tap().wait(5000).go(tester);
  I.see.page(driveDetailPageKey);
  I.see.multipleText('Test Drive - Integration Test', 2);
}

void main() {
  group('Drive Tests - Logged In Users', () {
    testWidgets('Create public drive from drive detail page', (tester) async {
      await runPreConditionUserLoggedIn(tester);
      await testCreatePublicDriveFromNewButton(tester);
    });
  });
}
