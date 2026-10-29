import 'package:ardrive/components/upload_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Share offers in the note after an upload. It follows the files the
/// upload covered, the same number the note counts, not only those the last
/// try sent.
void main() {
  group('one file shares the file', () {
    for (final drivePublic in [true, false]) {
      for (final inDriveRoot in [true, false]) {
        test('public: $drivePublic, in the root: $inDriveRoot', () {
          expect(
            uploadSavedShare(
              fileCount: 1,
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

  test('one file whose id is not known offers no Share', () {
    expect(
      uploadSavedShare(
          fileCount: 1, fileIds: [], inDriveRoot: false, drivePublic: true),
      UploadSavedShare.none,
    );
  });

  test(
      'three files of which a retry sent one: shared as three, never as that '
      'one file', () {
    expect(
      uploadSavedShare(
          fileCount: 3, fileIds: ['b'], inDriveRoot: false, drivePublic: true),
      UploadSavedShare.folder,
    );
    expect(
      uploadSavedShare(
          fileCount: 3, fileIds: ['b'], inDriveRoot: true, drivePublic: false),
      UploadSavedShare.none,
    );
  });

  test('several files in a public folder share that folder', () {
    expect(
      uploadSavedShare(
          fileCount: 2,
          fileIds: ['a', 'b'],
          inDriveRoot: false,
          drivePublic: true),
      UploadSavedShare.folder,
    );
  });

  test("several files in a public drive's root share the drive", () {
    expect(
      uploadSavedShare(
          fileCount: 2,
          fileIds: ['a', 'b'],
          inDriveRoot: true,
          drivePublic: true),
      UploadSavedShare.drive,
    );
  });

  test(
      'several files in a private drive offer no Share, folder or root: '
      "either share carries the drive's key", () {
    for (final inDriveRoot in [true, false]) {
      expect(
        uploadSavedShare(
            fileCount: 2,
            fileIds: ['a', 'b'],
            inDriveRoot: inDriveRoot,
            drivePublic: false),
        UploadSavedShare.none,
      );
    }
  });
}
