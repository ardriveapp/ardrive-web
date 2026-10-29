import 'package:ardrive/components/upload_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Share offers in the note after an upload.
void main() {
  group('one file shares the file', () {
    for (final drivePublic in [true, false]) {
      for (final inDriveRoot in [true, false]) {
        test('public: $drivePublic, in the root: $inDriveRoot', () {
          expect(
            uploadSavedShare(
              fileIds: ['a'],
              inDriveRoot: inDriveRoot,
              drivePublic: drivePublic,
            ),
            UploadSavedShare.file,
          );
        });
      }
    }
  });

  test('several files in a public folder share that folder', () {
    expect(
      uploadSavedShare(
          fileIds: ['a', 'b'], inDriveRoot: false, drivePublic: true),
      UploadSavedShare.folder,
    );
  });

  test("several files in a public drive's root share the drive", () {
    expect(
      uploadSavedShare(
          fileIds: ['a', 'b'], inDriveRoot: true, drivePublic: true),
      UploadSavedShare.drive,
    );
  });

  test(
      'several files in a private drive offer no Share, folder or root: '
      "either share carries the drive's key", () {
    for (final inDriveRoot in [true, false]) {
      expect(
        uploadSavedShare(
            fileIds: ['a', 'b'], inDriveRoot: inDriveRoot, drivePublic: false),
        UploadSavedShare.none,
      );
    }
  });
}
