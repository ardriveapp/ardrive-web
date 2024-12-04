import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

void main() {
  group('Snapshot Tests', () {
    testWidgets('Create a snapshot of the drive detail page', (tester) async {
      await runPreConditionUserLoggedIn(tester);
      await testCreateSnapshot(tester);
    });
  });
}

Future<void> testCreateSnapshot(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.publicDriveButton('drive test snapshot').tap().wait(500).go();
  await i.see.newButton().tap().wait(500).go();
  await i.see.button('Advanced').tap().wait(100).go();
  await i.see.button('New Snapshot').tap().wait(500).go();
  await i.see.button('PROCEED').tap().wait(10000).go();
  await i.see.button('UPLOAD').tap().wait(10000).go();
  i.see.text('Success');
  await i.see.button('OK').tap().wait(100).go();
}

Future<void> testCreatePrivateSnapshot(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.privateDriveButton('drive test snapshot private').tap().go();
  await i.wait(500);
  await i.see.newButton().tap().wait(500).go();
  await i.see.button('Advanced').tap().wait(100).go();
  await i.see.button('New Snapshot').tap().wait(500).go();
  await i.see.button('PROCEED').tap().wait(10000).go();
  await i.see.button('UPLOAD').tap().wait(10000).go();
  i.see.text('Success');
  await i.see.button('OK').tap().wait(100).go();
}
