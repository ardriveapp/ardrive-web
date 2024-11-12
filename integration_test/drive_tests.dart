import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

Future<void> testCreateDriveFromEmptyPage(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.button('Create new public drive').tap().wait(100).go();
  await i.see.textField('driveNameTextField').enterText('Test Drive').go();
  await i.see.button('CREATE').tap().wait(5000).go();
  i.see.page('driveDetailPage');
  i.see.multipleText('Test Drive', 2);
}

/// Pre-condition: User must be logged in
Future<void> testCreatePublicDriveFromNewButton(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.newButton().tap().wait(1000).go();
  await i.see.button('New Drive').tap().wait(1000).go();
  await i.see
      .textField(driveNameTextFieldKey)
      .enterText('Test Drive - Integration Test')
      .go();
  await i.see.buttonByKey(drivePrivateButtonKey).tap().wait(500).go();
  await i.see.buttonByKey(drivePublicButtonKey).tap().wait(500).go();
  await i.see.buttonByKey(createDriveButtonKey).tap().wait(5000).go();
  i.see.page(driveDetailPageKey);
  i.see.multipleText('Test Drive - Integration Test', 2);
}

void main() {
  group('Drive Tests - Logged In Users', () {
    testWidgets('Create public drive from drive detail page', (tester) async {
      await runPreConditionUserLoggedIn(tester);
      await testCreatePublicDriveFromNewButton(tester);
    });
  });
}
