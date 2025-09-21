import 'package:ardrive_io/src/utils/mime_type_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('lookupMimeType function', () {
    const pathToMimeMapping = <String, String?>{
      '.my.file.tar.gz': 'application/gzip',
      'abcdefghijklmnñopqrstuvwxyz.tar.gz': 'application/gzip',
      'path/to/my/file.tar.gz': 'application/gzip',
      'path/to/my/file.gz': 'application/gzip',
      'path/to/my/file.tgz': 'application/gzip',
      'path/to/my/non tar/file.iso': 'application/x-iso9660-image',
      'ardrive.png': 'image/png',
      '.tar.gz': 'application/gzip',
      'my.non.tar.gz.file': null,
      'where\'s waldo.tar.gz.': null,
    };

    test('returns the expected mime type', () {
      for (final path in pathToMimeMapping.keys) {
        final expectedMime = pathToMimeMapping[path];
        final mime = lookupMimeType(path);
        expect(mime, expectedMime);
      }
    });
  });

  group('lookupMimeTypeWithDefaultType function', () {
    const pathToMimeMapping = <String, String?>{
      '.my.file.tar.gz': 'application/gzip',
      'abcdefghijklmnñopqrstuvwxyz.tar.gz': 'application/gzip',
      'path/to/my/file.tar.gz': 'application/gzip',
      'path/to/my/file.gz': 'application/gzip',
      'path/to/my/file.tgz': 'application/gzip',
      'path/to/my/non tar/file.iso': 'application/x-iso9660-image',
      'ardrive.png': 'image/png',
      '.tar.gz': 'application/gzip',
      'my.non.tar.gz.file': octetStream,
      'where\'s waldo.tar.gz.': octetStream,
    };

    const pathToMimeMappingUpperCase = <String, String?>{
      '.my.file.TAR.GZ': 'application/gzip',
      'abcdefghijklmnñopqrstuvwxyz.tar.GZ': 'application/gzip',
      'path/to/my/file.TAR.GZ': 'application/gzip',
      'path/to/my/file.GZ': 'application/gzip',
      'path/to/my/file.tGZ': 'application/gzip',
      'path/to/my/non tar/file.ISO': 'application/x-iso9660-image',
      'ardrive.PNG': 'image/png',
      '.tar.GZ': 'application/gzip',
      'my.non.tar.GZ.file': octetStream,
      'where\'s waldo.TAR.gz.': octetStream,
    };

    test('returns the expected mime type', () {
      for (final path in pathToMimeMapping.keys) {
        final expectedMime = pathToMimeMapping[path];
        final mime = lookupMimeTypeWithDefaultType(path);
        expect(mime, expectedMime);
      }
    });

    test('returns the expected mime type when written in uppercase', () {
      for (final path in pathToMimeMappingUpperCase.keys) {
        final expectedMime = pathToMimeMappingUpperCase[path];
        final mime = lookupMimeTypeWithDefaultType(path);
        expect(mime, expectedMime);
      }
    });

    test(
        'returns the application/octet-stream type when not provided a mime type',
        () {
      final mime =
          lookupMimeTypeWithDefaultType('path/some_file_without_extension');
      expect(mime, octetStream);
    });
  });
}
