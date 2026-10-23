import 'package:ardrive/library/domain/library_config.dart';
import 'package:ardrive/library/presentation/library_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _folder = 'aaaaaaaa-0000-4000-8000-000000000001';

LibraryConfig _config(LibraryScope scope) => LibraryConfig(
      version: 1,
      driveId: _drive,
      rootFolderId: '41520b33-28c1-4892-886b-b845a5709085',
      scope: scope,
      privacy: 'public',
      owner: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
      snapshot: const LibrarySnapshot(path: 'snapshot', txId: 't', tags: {}),
      title: 'Library',
      description: '',
      images: const LibraryImages(),
      publishedAt: null,
      viewer: null,
    );

void main() {
  group('libraryLink', () {
    final page = Uri.parse('https://turbo-gateway.com/abc/#/folders/old');

    test('is the page itself for the root', () {
      expect(libraryLink(page: page), 'https://turbo-gateway.com/abc/#/');
    });

    test('names a folder, and a file in it', () {
      expect(
        libraryLink(page: page, folderId: _folder, fileId: 'f'),
        'https://turbo-gateway.com/abc/#/folders/$_folder?file=f',
      );
    });
  });

  group('openInArDriveUrl', () {
    test('opens a drive library at its drive', () {
      expect(
        openInArDriveUrl(_config(const LibraryDriveScope())),
        'https://app.ardrive.io/#/drives/$_drive',
      );
    });

    test('is not offered for a folder library, which would reach its drive',
        () {
      expect(
          openInArDriveUrl(_config(const LibraryFolderScope(_folder))), isNull);
    });
  });
}
