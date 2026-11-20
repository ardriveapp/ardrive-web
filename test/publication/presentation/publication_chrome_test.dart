import 'package:ardrive/publication/presentation/publication_chrome.dart';
import 'package:flutter_test/flutter_test.dart';

const _folder = 'aaaaaaaa-0000-4000-8000-000000000001';

void main() {
  group('publicationLink', () {
    final page = Uri.parse('https://turbo-gateway.com/abc/#/folders/old');

    test('is the page itself for the root', () {
      expect(publicationLink(page: page), 'https://turbo-gateway.com/abc/#/');
    });

    test('names a folder, and a file in it', () {
      expect(
        publicationLink(page: page, folderId: _folder, fileId: 'f'),
        'https://turbo-gateway.com/abc/#/folders/$_folder?file=f',
      );
    });

    group('on a page opened with the key in its link', () {
      const key = 'Zm9vYmFyYmF6cXV4cXV1eHF1dXhxdXV4cXV1eHF1dXg';
      final keyed =
          Uri.parse('https://turbo-gateway.com/abc/#/folders/old?k=$key');

      test('carries the key, after the #, to the root', () {
        expect(publicationLink(page: keyed),
            'https://turbo-gateway.com/abc/#/?k=$key');
      });

      test('carries the key to a folder, and a file in it', () {
        expect(
          publicationLink(page: keyed, folderId: _folder, fileId: 'f'),
          'https://turbo-gateway.com/abc/#/folders/$_folder?file=f&k=$key',
        );
        expect(publicationLink(page: keyed, folderId: _folder),
            'https://turbo-gateway.com/abc/#/folders/$_folder?k=$key');
      });

      test('and nothing else from the page link', () {
        final noisy = Uri.parse(
            'https://turbo-gateway.com/abc/?x=1#/folders/old?file=g&k=$key&q=2');
        expect(publicationLink(page: noisy, folderId: _folder),
            'https://turbo-gateway.com/abc/?x=1#/folders/$_folder?k=$key');
      });
    });

    test('a page whose link has no key gives links without one', () {
      expect(publicationLink(page: page, folderId: _folder),
          'https://turbo-gateway.com/abc/#/folders/$_folder');
    });
  });
}
