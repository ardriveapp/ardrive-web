import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'integration_test_cli_arguments.dart';
import 'login_tests.dart' as login_test;
import 'logout_test.dart' as logout_test;
import 'onboarding_tests.dart' as onboarding_test;
import 'utils.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  onboarding_test.main();
  login_test.main();
  logout_test.main();
  // TODO: re-enable commented tests
  // snapshot_test.main();
  // drive_test.main();
  // folder_test.main();
  //upload_test.main();
  //manifest_test.main();
}

bool hasServicesInitialized = false;

Future<void> initApp(WidgetTester tester, {bool deleteDatabase = false}) async {
  if (!hasServicesInitialized) {
    await initializeServices(deleteDatabase: deleteDatabase);
    hasServicesInitialized = true;
  }

  await tester.pumpWidget(App(
    runningFromFlutterTest: true,
    key: UniqueKey(),
  ));

  await waitAndUpdate(tester, 2);
}

final testCaseList = testCases.isNotEmpty
    ? testCases.split(',').map((s) => s.trim()).toSet()
    : <String>{};

Future<void> logoutUser() async {
  final ardriveAuth = arDriveAppKey.currentState!.context.read<ArDriveAuth>();
  final profileCubit = arDriveAppKey.currentState!.context.read<ProfileCubit>();

  await ardriveAuth.logout();
  profileCubit.logoutProfile();
}
