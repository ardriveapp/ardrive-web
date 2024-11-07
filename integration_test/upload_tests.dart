import 'dart:typed_data';

import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/utils/ardrive_io_integration_test.dart';
import 'package:ardrive/utils/widget_keys.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';
import 'login_tests.dart';
import 'utils.dart';

Future<void> testPublicFileUpload(WidgetTester tester) async {
  await I.see.newButton().tap().wait(100).go(tester);
  await I.see.text('Upload File(s)').wait(100).go(tester);
  String randomFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.txt';
  await setNewFileUploadResult(tester, randomFileName);
  await I.waitToSee(uploadReadyModalKey, tester, 30);
  await I.see.button('UPLOAD').tap().wait(100).go(tester);
  await I.wait(10 * 1000); // 10 seconds
  await I.see.text(randomFileName).tap().wait(100).go(tester);
  I.see.multipleText(randomFileName, 2);
}

Future<void> testPublicMultipleFileUpload(
    WidgetTester tester, int numberOfFiles, int size) async {
  final newButton = find.text('New');
  expect(newButton, findsOneWidget);

  await tester.tap(newButton);

  await waitAndUpdate(tester, 1);

  final findUploadFilesButton = find.text('Upload File(s)');
  expect(findUploadFilesButton, findsOneWidget);

  await waitAndUpdate(tester, 1);

  List<String> randomFileNames = [];

  for (int i = 0; i < numberOfFiles; i++) {
    randomFileNames
        .add('test_${DateTime.now().millisecondsSinceEpoch + i}.txt');
  }

  final context = arDriveAppKey.currentState!.context;

  final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;

  List<IOFile> files = [];

  for (var fileName in randomFileNames) {
    files.add(
      await IOFileAdapter().fromReadStreamGenerator(
        ([_, __]) => Stream.value(Uint8List(size)),
        size,
        name: fileName,
        lastModifiedDate: DateTime.now(),
      ),
    );
  }

  ardriveIO.setPickFileResultList(files);

  await tester.tap(findUploadFilesButton);

  await waitToSee(tester: tester, widgetType: UploadReadyModalBase);

  await waitAndUpdate(tester, 1);

  final uploadButton = find.text('UPLOAD');
  expect(uploadButton, findsOneWidget);

  await tester.tap(uploadButton);

  // time to upload
  await waitAndUpdate(tester, 10 * randomFileNames.length);

  /// verify the file is uploaded
  for (var fileName in randomFileNames) {
    final findFile = find.text(fileName);
    expect(findFile, findsOneWidget);
  }

  /// click on the file to open the file details page
  for (var fileName in randomFileNames) {
    await tester.tap(find.text(fileName));

    await waitAndUpdate(tester, 1);

    final detailsPanel = find.byType(DetailsPanel);
    expect(detailsPanel, findsOneWidget);

    /// find now two file names, one in the breadcrumb and one in the sidebar
    final findFileName = find.text(fileName);
    expect(findFileName, findsNWidgets(2));
  }

  /// close the app
  await tester.pumpAndSettle();
}

Future<void> setNewFileUploadResult(
    WidgetTester tester, String fileName) async {
  final context = arDriveAppKey.currentState!.context;

  final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;

  ardriveIO.setPickFileResultList([await testFileUpload(fileName)]);
}

void main() {
  group('Upload Tests', () {
    testWidgets('Test public file upload', (tester) async {
      await initApp(tester, deleteDatabase: true);
      await testLoginSuccess(tester);
      await I.wait(10000);
      await testPublicFileUpload(tester);
    });
  });
}
