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
  });
}
