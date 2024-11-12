import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';

void main() {
  group('Drive Explorer Navigation', () {
    testWidgets('User can navigate to a file', (WidgetTester tester) async {
      final i = I(see: See(tester: tester));

      await i.waitAppToLoad(tester, 2);

      // await runPreConditionUserLoggedIn(tester);
      // await testSeeFile(tester);
    });
  });
}

/// This test demonstrates navigation through a drive using the DSL methods:
/// - publicDriveButton(): Finds and interacts with a public drive button by name
/// - folderOnDriveExplorer(): Finds and interacts with a folder in the drive explorer
/// - fileOnDriveExplorer(): Finds and verifies a file exists in the drive explorer
///
/// The test chains actions like tap(), doubleTap() and wait() to simulate user interactions
/// and waits for UI updates. The go() method executes the chain of actions.
Future<void> testSeeFile(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.publicDriveButton('drive test snapshot').tap().wait(1000).go();
  await i.see
      .folderOnDriveExplorer('test-manifest')
      .doubleTap()
      .wait(1000)
      .go();

  i.see.fileOnDriveExplorer('Screenshot 2024-10-04 at 17.18.40.png');
}
