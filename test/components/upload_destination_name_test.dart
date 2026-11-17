import 'package:ardrive/components/upload_form.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _Params extends Mock implements UploadParams {}

class _Folder extends Mock implements FolderEntry {}

class _Drive extends Mock implements Drive {}

void main() {
  UploadParams params({String? parentFolderId}) {
    final folder = _Folder();
    when(() => folder.name).thenReturn('Bundled Drive 10-18');
    when(() => folder.parentFolderId).thenReturn(parentFolderId);
    final drive = _Drive();
    when(() => drive.name).thenReturn('Demo Drive');
    final p = _Params();
    when(() => p.targetFolder).thenReturn(folder);
    when(() => p.targetDrive).thenReturn(drive);
    return p;
  }

  test('the drive root is named for its drive', () {
    expect(uploadDestinationName(params()), 'Demo Drive');
  });

  test('a folder is named for itself', () {
    expect(uploadDestinationName(params(parentFolderId: 'root')),
        'Bundled Drive 10-18');
  });
}
