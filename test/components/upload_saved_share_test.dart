import 'package:ardrive/components/upload_form.dart';
import 'package:flutter_test/flutter_test.dart';

/// What Share offers in the note after an upload.
void main() {
  test('one file shares the file', () {
    expect(
      uploadSavedShare(fileIds: ['a'], inDriveRoot: true, drivePublic: false),
      UploadSavedShare.file,
    );
  });

  test('several files in a folder share that folder', () {
    expect(
      uploadSavedShare(
          fileIds: ['a', 'b'], inDriveRoot: false, drivePublic: false),
      UploadSavedShare.folder,
    );
  });

  test('several files in a public drive\'s root share the drive', () {
    expect(
      uploadSavedShare(
          fileIds: ['a', 'b'], inDriveRoot: true, drivePublic: true),
      UploadSavedShare.drive,
    );
  });

  test(
      'several files in a private drive\'s root offer no Share: the drive\'s '
      'key would open everything in it', () {
    expect(
      uploadSavedShare(
          fileIds: ['a', 'b'], inDriveRoot: true, drivePublic: false),
      UploadSavedShare.none,
    );
  });
}
