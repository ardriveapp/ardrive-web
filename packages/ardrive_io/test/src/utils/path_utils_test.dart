import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getFolderNameFromPath method', () {
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
  group('getDirname method', () {
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

  group('getFileExtension method', () {
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
        contentType: octetStream,
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

  group('getFileTypeFromMime method', () {
    test('should return the file type from mimetype', () {
      final type = getFileTypeFromMime(contentType: 'application/pdf');
      expect(type, 'pdf');
    });

    test('should return the file type for a different mimetype', () {
      final type = getFileTypeFromMime(contentType: 'image/jpeg');
      expect(type, 'jpeg');
    });

    test('should return null for an empty string', () {
      final type = getFileTypeFromMime(contentType: '');
      expect(type, '');
    });
  });

  group('getBasenameWithoutExtension method', () {
    test('should return the basename without extension', () {
      final basename = getBasenameWithoutExtension(
        filePath: '/hola/que/tal/file.pdf',
      );
      expect(basename, 'file');
    });

    test('should return the basename without extension', () {
      final basename = getBasenameWithoutExtension(
        filePath: '/hola/que/tal/file.pdf.txt',
      );
      expect(basename, 'file.pdf');
    });

    test('should return the basename for a different file path', () {
      final basename = getBasenameWithoutExtension(
        filePath: '/another/path/to/different.file',
      );
      expect(basename, 'different');
    });

    test('should return the basename for a file path without extension', () {
      final basename = getBasenameWithoutExtension(
        filePath: '/path/to/file',
      );
      expect(basename, 'file');
    });

    test('should return an empty string for an empty string', () {
      final basename = getBasenameWithoutExtension(
        filePath: '',
      );
      expect(basename, '');
    });
  });
}
