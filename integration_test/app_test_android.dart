import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'login_tests_mobile.dart' as login_tests_mobile;
import 'logout_test_mobile.dart' as logout_test_mobile;
import 'onboarding_tests_mobile.dart' as onboarding_test_mobile;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  onboarding_test_mobile.main();
  login_tests_mobile.main();
  logout_test_mobile.main();
}

bool hasServicesInitialized = false;
