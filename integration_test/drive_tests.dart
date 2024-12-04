import 'package:ardrive/utils/widget_keys.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

Future<void> testCreateDriveFromEmptyPage(WidgetTester tester) async {
  final i = I(see: See(tester: tester));
  final randomDriveName =
      'Test Drive - Integration Test ${DateTime.now().millisecondsSinceEpoch}';

  await i.see.button('Create new public drive').tap().wait(100).go();
  await i.see.textField('driveNameTextField').enterText(randomDriveName).go();
  await i.see.button('CREATE').tap().wait(5000).go();
  i.see.page('driveDetailPage');
  i.see.multipleText(randomDriveName, 2);
}

/// Pre-condition: User must be logged in
Future<void> testCreatePublicDriveFromNewButton(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.newButton().tap().wait(2000).go();
  final String randomDriveName =
      'Test Drive - Integration Test ${DateTime.now().millisecondsSinceEpoch}';
  await i.see.button('New Drive').tap().wait(2000).go();
  await i.see.textField(driveNameTextFieldKey).enterText(randomDriveName).go();
  await i.see.buttonByKey(drivePrivateButtonKey).tap().wait(500).go();
  await i.see.buttonByKey(drivePublicButtonKey).tap().wait(500).go();
  await i.see.buttonByKey(createDriveButtonKey).tap().wait(5000).go();
  i.see.page(driveDetailPageKey);
  i.see.multipleText(randomDriveName, 2);
}

Future<void> testCreatePrivateDriveFromNewButton(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.newButton().tap().wait(2000).go();
  final String randomDriveName =
      'Test Drive - Integration Test ${DateTime.now().millisecondsSinceEpoch}';
  await i.see.button('New Drive').tap().wait(2000).go();
  await i.see
      .textField(driveNameTextFieldKey)
      .enterText(randomDriveName)
      .wait(500)
      .go();
  await i.see.buttonByKey(createDriveButtonKey).tap().wait(5000).go();
  i.see.page(driveDetailPageKey);
  i.see.multipleText(randomDriveName, 2);
}

void main() {
  group('Drive Tests - Logged In Users', () {
    testWidgets('Create public and private drive from drive detail page',
        (tester) async {
      await runPreConditionUserLoggedIn(tester);
      await testCreatePublicDriveFromNewButton(tester);
      await testCreatePrivateDriveFromNewButton(tester);
    });
  });
}
