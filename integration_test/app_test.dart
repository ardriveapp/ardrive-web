import 'package:ardrive/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'drive_tests.dart' as drive_tests;
import 'folder_tests.dart' as folder_tests;
import 'integration_test_cli_arguments.dart';
import 'login_tests.dart' as login_tests;
import 'logout_test.dart' as logout_test;
import 'onboarding_tests.dart' as onboarding_test;
import 'utils.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  onboarding_test.main();
  login_tests.main();
  logout_test.main();
  drive_tests.main();
  folder_tests.main();
}

bool hasServicesInitialized = false;

Future<void> initApp(WidgetTester tester, {bool deleteDatabase = false}) async {
  await initializeServices(deleteDatabase: deleteDatabase);
  hasServicesInitialized = true;

  await tester.pumpWidget(const App(
    runningFromFlutterTest: true,
  ));

  await waitAndUpdate(tester, 2);
}

final testCaseList = testCases.isNotEmpty
    ? testCases.split(',').map((s) => s.trim()).toSet()
    : <String>{};
