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
import 'utils.dart';
import 'logout_test.dart' as logout_test;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  //onboarding_test.main();
  login_test.main();
  logout_test.main(); 
  //snapshot_test.main();
  //drive_test.main();
  //folder_test.main();
  //upload_test.main();
  //manifest_test.main();
}

Future<void> runAllTests(WidgetTester tester) async {
  // await initApp(tester);

  // await I.waitAppToLoad(tester, 3);
  // await testSignUpAndOnboarding(tester);
  // await testCreateDriveFromEmptyPage(tester);
  // await I.wait(3);
  // await testCreateFolderFromEmptyPage(tester);
  // await I.wait(3);

  // await logoutUser();

  // await login_test.testLoginSuccess(tester);
  // // time to sync
  // await I.wait(5);
  // await testPublicFileUpload(tester);
  // // time to sync
  // await I.wait(5);
  // await testPublicMultipleFileUpload(tester, 5, const KiB(5).size);
  // // time to sync
  // await I.wait(5);
  // await tester.pumpAndSettle();
}

Future<void> initApp(WidgetTester tester, {bool deleteDatabase = false}) async {
  await initializeServices(deleteDatabase: deleteDatabase);

  await tester.pumpWidget(App(
    runningFromFlutterTest: true,
    key: UniqueKey(),
  ));

  await waitAndUpdate(tester, 2);
}

void newUserTests() {
  group('New User Tests', () {
    testWidgets(
        'should complete the onboarding flow successfully creating a new wallet',
        (tester) async {
      // await initApp(tester);

      // await testSignUpAndOnboarding(tester);

      // await I.wait(3);

      // if (testCaseList.contains('drive')) {
      //   await testCreateDriveFromEmptyPage(tester);
      //   createdDrive = true;
      // }

      // await I.wait(1);

      // if (testCaseList.contains('folder')) {
      //   await testCreateFolderFromEmptyPage(tester);
      //   createdFolder = true;
      // }

      // await waitAndUpdate(tester, 3);

      // if (testCaseList.contains('upload')) {
      //   if (!createdDrive && !createdFolder) {
      //     throw Exception('No drive or folder created');
      //   }

      //   await testPublicFileUpload(tester);
      // }

      // await tester.pumpAndSettle();
    });
  });
}

Future<void> existingUserTests() async {
  testWidgets('should complete the login flow successfully', (tester) async {
    await initApp(tester);
    await login_test.testLoginSuccess(tester);

    // if (testCaseList.contains('public_drive')) {
    //   await I.wait(5000);
    //   await testCreatePublicDriveFromDriveDetailPage(tester);
    // }

    // if (testCaseList.contains('public_folder')) {
    //   await testCreatePublicFolderFromDriveDetailPage(tester);
    // }

    // if (testCaseList.contains('upload')) {
    //   // time to sync
    //   await waitAndUpdate(tester, 5);

    //   await testPublicFileUpload(tester);
    // }

    // if (testCaseList.contains('uploadMultipleFiles')) {
    //   // time to sync
    //   await I.wait(5);

    //   await testPublicMultipleFileUpload(tester, 5, const KiB(1).size);
    // }

    // if (testCaseList.contains('upload_excessive_files')) {
    //   await testPublicMultipleFileUpload(tester, 1000, const KiB(50).size);
    // }

    // if (testCaseList.contains('manifest_creation')) {
    //   await I.wait(5);

    //   await testManifestCreation(tester);
    // }

    await tester.pumpAndSettle();
  });
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
