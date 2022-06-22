import 'package:ardrive/utils/mime_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('customLookupMimeType function', () {
    const tarGzPaths = [
      '.my.file.tar.gz',
      'another file that is cool.tar.gz',
      'abcdefghijklmnñopqrstuvwxyz.tar.gz',
      'path/to/my/file.tar.gz',
    ];
    const nonTarGzPaths = [
      '.tar.gz',
      'my.non.tar.gz.file',
      'ardrive.png',
      'where\'s waldo.tar.gz.',
      'path/to/my/non tar/file.iso',
    ];

    test('returns the expected value for .tar.gz files', () {
      tarGzPaths.forEach((path) {
        final mime = customLookupMimeType(path);
        expect(mime, applicationXTar);
      });
    });

    test('returns the expected value for NON .tar.gz files', () {
      nonTarGzPaths.forEach((path) {
        final mime = customLookupMimeType(path);
        expect(mime == applicationXTar, false);
      });
    });
  });
}
