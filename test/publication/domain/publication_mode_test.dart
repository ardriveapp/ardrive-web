import 'package:ardrive/publication/domain/publication_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => PublicationMode.debugSet(null));

  group('PublicationMode.detect', () {
    test('is on when the page names its settings', () {
      PublicationMode.detect(() => 'publication.json');

      expect(PublicationMode.isOn, isTrue);
      expect(PublicationMode.settingsPath, 'publication.json');
    });

    test("keeps the page's own title, for a publication only", () {
      PublicationMode.detect(() => 'publication.json',
          readTitle: () => " Phil's <Archive> ");
      expect(PublicationMode.pageTitle, "Phil's <Archive>");

      PublicationMode.detect(() => null, readTitle: () => 'ArDrive');
      expect(PublicationMode.pageTitle, isNull);
    });

    test('is off when the page has no tag', () {
      PublicationMode.detect(() => null);

      expect(PublicationMode.isOn, isFalse);
      expect(PublicationMode.settingsPath, isNull);
    });
  });

  group('parsePublicationMetaContent', () {
    test('accepts a plain relative path, trimmed', () {
      expect(parsePublicationMetaContent(' publication.json '),
          'publication.json');
      expect(parsePublicationMetaContent('settings/publication.json'),
          'settings/publication.json');
    });

    for (final content in [
      null,
      '',
      '   ',
      'https://evil.example/publication.json',
      '//evil.example/publication.json',
      '/publication.json',
      '../publication.json',
      'a/../publication.json',
      './publication.json',
      'publication.json?x=1',
      'publication.json#x',
      'javascript:alert(1)',
      'a//publication.json',
    ]) {
      test('switches publication mode off for "$content"', () {
        expect(parsePublicationMetaContent(content), isNull);
      });
    }
  });
}
