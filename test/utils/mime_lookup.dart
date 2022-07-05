import 'package:ardrive/utils/mime_lookup.dart';
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
}
