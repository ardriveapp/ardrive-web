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
  await I.see.publicDriveButton('drive test snapshot').tap().wait(500).go(tester);
  await I.see.newButton().tap().wait(500).go(tester);
  await I.see.button('Advanced').tap().wait(100).go(tester);
  await I.see.button('New Snapshot').tap().wait(500).go(tester);
  await I.see.button('PROCEED').tap().wait(10000).go(tester);
  await I.see.button('UPLOAD').tap().wait(10000).go(tester);
  I.see.text('Success');
  await I.see.button('OK').tap().wait(100).go(tester);
}

Future<void> testCreatePrivateSnapshot(WidgetTester tester) async {
  await I.see.privateDriveButton('drive test snapshot private').tap().wait(500).go(tester);
  await I.see.newButton().tap().wait(500).go(tester);
  await I.see.button('Advanced').tap().wait(100).go(tester);
  await I.see.button('New Snapshot').tap().wait(500).go(tester);
  await I.see.button('PROCEED').tap().wait(10000).go(tester);
  await I.see.button('UPLOAD').tap().wait(10000).go(tester);
  I.see.text('Success');
  await I.see.button('OK').tap().wait(100).go(tester);
}

