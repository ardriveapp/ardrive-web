import 'package:ardrive/main.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'drive_tests.dart' as drive_tests;
import 'folder_tests.dart' as folder_tests;
import 'integration_test_cli_arguments.dart';
import 'login_tests.dart' as login_tests;
import 'login_tests_mobile.dart' as login_tests_mobile;
import 'logout_test.dart' as logout_test;
import 'logout_test_mobile.dart' as logout_test_mobile;
import 'onboarding_tests.dart' as onboarding_test;
import 'onboarding_tests_mobile.dart' as onboarding_test_mobile;
import 'utils.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  if (AppPlatform.isAndroid) {
    onboarding_test_mobile.main();
    login_tests_mobile.main();
    logout_test_mobile.main();
  } else {
    onboarding_test.main();
    login_tests.main();
    logout_test.main();
    drive_tests.main();
    folder_tests.main();
  }
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
