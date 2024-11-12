import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

void main() {
  group('Drive Explorer Navigation', () {
    testWidgets('User can navigate to a file', (WidgetTester tester) async {
      await runPreConditionUserLoggedIn(tester);
      await testSeeFile(tester);
    });
  });
}

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
