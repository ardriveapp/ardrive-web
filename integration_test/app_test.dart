// ignore_for_file: avoid_print

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'integration_test_cli_arguments.dart';
import 'login_tests.dart' as login_tests;
import 'login_tests_mobile.dart' as login_tests_mobile;
import 'utils.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  if (AppPlatform.isAndroid) {
    print('Running mobile tests');
    // onboarding_test_mobile.main();
    login_tests_mobile.main();
    // logout_test_mobile.main();
  } else {
    // onboarding_test.main();
    login_tests.main();
    // logout_test.main();
    // upload_test.main();
    // snapshot_test.main();
    // drive_test.main();
    // folder_test.main();
    // manifest_test.main();
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

Future<void> logoutUser() async {
  final ardriveAuth = arDriveAppKey.currentState!.context.read<ArDriveAuth>();
  final profileCubit = arDriveAppKey.currentState!.context.read<ProfileCubit>();

  await ardriveAuth.logout();
  profileCubit.logoutProfile();
}
