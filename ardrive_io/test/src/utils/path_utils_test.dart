import 'package:ardrive_io/src/io_exception.dart';
import 'package:ardrive_io/src/utils/path_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('test method getFolderNameFromPath', () {
    test('should return correct folder name', () {
      expect(getBasenameFromPath('some-folder'), 'some-folder');
      expect(getBasenameFromPath('/some-folder'), 'some-folder');
      expect(getBasenameFromPath('some_directory/some-folder'), 'some-folder');
      expect(getBasenameFromPath('/storage/emulated/0/Download/Upload folder'),
          'Upload folder');
    });

    test('should throw an EntityPathException when having a empty path', () {
      expect(() => getBasenameFromPath(''),
          throwsA(const TypeMatcher<EntityPathException>()));
    });
  });
  group('test method getDirname', () {
    test('should return correct dirname', () {
      expect(getDirname('/some-folder/file'), '/some-folder');
      expect(getDirname('/some-folder/path/file.png'), '/some-folder/path');
      expect(getDirname('/some_directory/some-folder'), '/some_directory');
      expect(getDirname('/storage/emulated/0/Download/Upload folder'),
          '/storage/emulated/0/Download');
    });

    test('should throw an EntityPathException when having a empty path', () {
      expect(() => getDirname(''),
          throwsA(const TypeMatcher<EntityPathException>()));
    });
  });

  group('test method getFileExtension', () {
    test('should return the extension from contentType and return with the .',
        () {
      /// .pdf
      final ext = getFileExtension(
          name: 'somefile_without_ext', contentType: 'application/pdf');
      expect(ext, '.pdf');
    });
    test('should return the extension from file name when and return with .',
        () {
      /// .pdf
      final ext =
          getFileExtension(name: 'file.pdf', contentType: 'application/pdf');
      expect(ext, '.pdf');
    });
    test('should return the extension from file name and return with .', () {
      final ext =
          getFileExtension(name: 'file.pdf', contentType: 'application/pdf');
      expect(ext, '.pdf');
    });

    test('should return the extension from file name without .', () {
      final ext = getFileExtension(
        name: 'file.pdf',
        contentType: 'application/pdf',
        withExtensionDot: false,
      );

      expect(ext, 'pdf');
    });

    test('should return the extension from mimetype name without .', () {
      final ext = getFileExtension(
        name: 'file',
        contentType: 'application/pdf',
        withExtensionDot: false,
      );

      expect(ext, 'pdf');
    });

    test('should return the extension from mimetype name without .', () {
      final ext = getFileExtension(
        name: 'file',
        contentType: 'application/octet-stream',
        withExtensionDot: false,
      );

      expect(ext, 'bin');
    });

    test('should return the extension from mimetype name with . ', () {
      final ext = getFileExtension(
        name: 'test!_·\$%d_%&·_',
        contentType: 'text/plain',
      );

      expect(ext, '.conf');
    });

    test('should return the extension from mimetype name without .', () {
      final ext = getFileExtension(
        name: 'test!_·\$%d_%&·_.txt',
        contentType: 'text/plain',
        withExtensionDot: false,
      );

      expect(ext, 'txt');
    });

    test('should return the extension from mimetype name without .', () {
      final ext = getFileExtension(
        name: 'test!_·\$%d_%&·_',
        contentType: 'text/plain',
        withExtensionDot: false,
      );

      expect(ext, 'conf');
    });
  });
}
