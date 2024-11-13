import 'dart:typed_data';

import 'package:ardrive/components/details_panel.dart';
import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/utils/ardrive_io_integration_test.dart';
import 'package:ardrive/utils/widget_keys.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dsl/dsl.dart';
import 'utils.dart';

Future<void> testSingleFileUpload(WidgetTester tester, bool isPublic) async {
  final i = I(see: See(tester: tester));

  if (isPublic) {
    await i.see.publicDriveButton('public drive').tap().wait(1000).go();
  } else {
    await i.see.privateDriveButton('private drive').tap().wait(100).go();
  }

  await i.see.newButton().tap().wait(300).go();
  String randomFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.txt';

  await setNewFileUploadResult(tester, randomFileName);

  await i.see.button('Upload File(s)').tap().wait(300).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  await i.see.button('UPLOAD').tap().wait(300).go();
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer(randomFileName).tap().wait(1000).go();
  i.see.multipleText(randomFileName, 2);
}

Future<void> testMultipleFileUpload(WidgetTester tester, bool isPublic) async {
  final i = I(see: See(tester: tester));

  if (isPublic) {
    await i.see.publicDriveButton('public drive').tap().wait(1000).go();
  } else {
    await i.see.privateDriveButton('private drive').tap().wait(100).go();
  }

  await i.see.newButton().tap().wait(300).go();
  final fileNames = await setListOfFilesForUpload(tester, 10, 1000);

  await i.see.button('Upload File(s)').tap().wait(300).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.wait(10 * 1000);

  for (var fileName in fileNames) {
    await i.see.fileOnDriveExplorer(fileName).tap().wait(1000).go();
    i.see.multipleText(fileName, 2);
  }
}

Future<void> testMultipleFileUploadAndUpdateManifest(
    WidgetTester tester, bool isPublic) async {
  final i = I(see: See(tester: tester));
  await i.see.publicDriveButton('auto-update-drive-test').tap().wait(1000).go();
  await i.see.newButton().tap().wait(300).go();
  final fileNames = await setListOfFilesForUpload(tester, 10, 1000);
  await i.see.button('Upload File(s)').tap().wait(300).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  const String manifestName = 'manifest';
  await i.wait(1000);
  await i.see
      .arDriveCheckboxByKey('auto-update-checkbox-$manifestName')
      .tap()
      .wait(1000)
      .go();
  await i.see.button('REVIEW').tap().wait(1000).go();
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.waitToSee('uploading-manifests-modal', tester, 30);
  await i.wait(10 * 1000);

  for (var fileName in fileNames) {
    await i.see.fileOnDriveExplorer(fileName).tap().wait(1000).go();
    i.see.multipleText(fileName, 2);
  }
}

Future<void> testMultipleFileUploadWithConflictResolution(
    WidgetTester tester) async {
  final i = I(see: See(tester: tester));
  await i.see.publicDriveButton('public drive').tap().wait(1000).go();
await i.see.newButton().tap().wait(300).go();
  final context = arDriveAppKey.currentState!.context;
  final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;

  /// all files are conflicting
  ardriveIO.setPickFileResultList([
    await testFileUpload('image.png'),
    await testFileUpload('arns.svg'),
  ]);

  await i.see.button('Upload File(s)').tap().wait(1000).go();
  i.see.text('Duplicate files found');
  await i.see.button('REPLACE').tap().wait(1000).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  i.see.text('Upload 2 files');
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer('image.png').tap().wait(1000).go();
  i.see.multipleText('image.png', 2);
  await i.see.fileOnDriveExplorer('arns.svg').tap().wait(1000).go();
  i.see.multipleText('arns.svg', 2);
}

Future<void> testMultipleFileUploadWithPartialConflictResolution(
    WidgetTester tester) async {
  final i = I(see: See(tester: tester));
  await i.see.publicDriveButton('public drive').tap().wait(1000).go();
  await i.see.newButton().tap().wait(300).go();
  final context = arDriveAppKey.currentState!.context;
  final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;

  /// all files are conflicting
  ardriveIO.setPickFileResultList([
    await testFileUpload('image.png'),
    await testFileUpload('arns.svg'),
    await testFileUpload('a_non_conflicting_file.png'),
  ]);

  await i.see.button('Upload File(s)').tap().wait(300).go();
  i.see.text('Duplicate files found');
  await i.see.button('SKIP').tap().wait(100).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  i.see.text('Upload 1 file');
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer('a_non_conflicting_file.png').tap().go();
  await i.wait(1000);
  i.see.multipleText('a_non_conflicting_file.png', 2);
}

Future<void> testMultipleFileUploadWithPartialConflictResolutionWithReplace(
    WidgetTester tester) async {
  final i = I(see: See(tester: tester));
  await i.see.publicDriveButton('public drive').tap().wait(1000).go();
  await i.see.newButton().tap().wait(300).go();
  final context = arDriveAppKey.currentState!.context;
  final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;

  /// all files are conflicting
  ardriveIO.setPickFileResultList([
    await testFileUpload('image.png'),
    await testFileUpload('arns.svg'),
    await testFileUpload('a_non_conflicting_file2.png'),
  ]);

  await i.see.button('Upload File(s)').tap().wait(300).go();
  i.see.text('Duplicate files found');
  await i.see.button('REPLACE').tap().wait(100).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  i.see.text('Upload 3 files');
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer('a_non_conflicting_file2.png').tap().go();
  await i.wait(1000);
  i.see.multipleText('a_non_conflicting_file2.png', 2);
}

Future<List<String>> setListOfFilesForUpload(
    WidgetTester tester, int numberOfFiles, int size) async {
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

  return randomFileNames;
}

Future<void> testSingleFileConflictResolution(WidgetTester tester) async {
  final i = I(see: See(tester: tester));
  await i.see.publicDriveButton('public drive').tap().wait(1000).go();
  await i.see.newButton().tap().wait(300).go();
  const String existingFileName = 'image.png';
  await setNewFileUploadResult(tester, existingFileName);

  await i.see.button('Upload File(s)').tap().wait(300).go();
  await i.waitToSee('upload-file-conflict', tester, 10);
  // i.see.text('A duplicate file found');

  /// one in the drive explorer and another one in the conflict resolution modal
  i.see.multipleText('image.png', 2);
  await i.see.button('REPLACE').tap().wait(100).go();
  await i.wait(10000);
  await i.see.button('UPLOAD').tap().go();
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer(existingFileName).tap().wait(1000).go();
  i.see.multipleText(existingFileName, 2);
}

Future<void> testAssignLicenseToFile(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  await i.see.publicDriveButton('public drive').tap().wait(1000).go();
  await i.see.newButton().tap().wait(300).go();
  String randomFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.txt';
  await setNewFileUploadResult(tester, randomFileName);
  await i.see.button('Upload File(s)').tap().wait(300).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  await chooseCCByLicense(tester, 'Attribution', 'Attribution (CC-BY)');
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer(randomFileName).tap().wait(1000).go();
  i.see.multipleText(randomFileName, 2);
}

Future<void> testThumbnailCheckbox(WidgetTester tester) async {
  final i = I(see: See(tester: tester));

  i.see.text('Upload with thumbnails');
}

Future<void> testAutoUpdateManifest(WidgetTester tester) async {
  final i = I(see: See(tester: tester));
  await i.see.publicDriveButton('auto-update-drive-test').tap().wait(1000).go();
  await i.see.newButton().tap().wait(300).go();
  String randomFileName = 'test_${DateTime.now().millisecondsSinceEpoch}.txt';
  await setNewFileUploadResult(tester, randomFileName);
  await i.see.button('Upload File(s)').tap().wait(300).go();
  await i.waitToSee(uploadReadyModalKey, tester, 30);
  i.see.text('Update Manifest(s)');
  const String manifestName = 'manifest';
  await i.wait(1000);
  await i.see
      .arDriveCheckboxByKey('auto-update-checkbox-$manifestName')
      .tap()
      .wait(1000)
      .go();
  await i.see.button('REVIEW').tap().wait(1000).go();
  await i.see.button('UPLOAD').tap().wait(1000).go();
  await i.waitToSee('uploading-manifests-modal', tester, 30);
  await i.wait(10 * 1000);
  await i.see.fileOnDriveExplorer(randomFileName).tap().wait(1000).go();
  i.see.multipleText(randomFileName, 2);
  await i.see.fileOnDriveExplorer(manifestName).tap().wait(1000).go();
  i.see.multipleText(manifestName, 2);
}

Future<void> chooseCCByLicense(WidgetTester tester, String license,
    String licenseLabelOnUploadReview) async {
  final i = I(see: See(tester: tester));

  await i.see.button('None').tap().wait(1000).go();
  await i.see.button('Creative Commons (CC)').tap().wait(1000).go();
  await i.see.button('CONFIGURE').tap().wait(1000).go();
  await i.see.button('Public Domain').tap().wait(1000).go();
  await i.see.button(license).tap().wait(1000).go();
  await i.see.button('NEXT').tap().wait(1000).go();
  i.see.text(licenseLabelOnUploadReview);
}

Future<void> chooseUDLLicense(WidgetTester tester, String license) async {
  final i = I(see: See(tester: tester));

  await i.see.button('None').tap().wait(1000).go();
  await i.see.button('Universal Data License (UDL)').tap().wait(1000).go();
  await i.see.button('CONFIGURE').tap().wait(1000).go();
  // TODO: find the license fee textfield
  // TODO: find the currency dropdown
  // TODO: find the commercial use
  // TODO: find the derivations
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
    testWidgets('Test Single File Upload', (tester) async {
      await runPreConditionUserLoggedIn(tester);
      // await testMultipleFileUpload(tester, true);
      await testMultipleFileUploadAndUpdateManifest(tester, true);
      // await testMultipleFileUploadWithPartialConflictResolutionWithReplace(
      //     tester);
      // await testMultipleFileUploadWithPartialConflictResolution(tester);
      // await testMultipleFileUploadWithPartialConflictResolutionWithReplace(
      //   tester,
      // );
      // await testAutoUpdateManifest(tester);
      // await testAssignLicenseToFile(tester);
      // await testSingleFileUpload(tester, true);
      // await testSingleFileUpload(tester, false);
      // await testSingleFileConflictResolution(tester);
    });
  });
}
