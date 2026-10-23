import 'package:ardrive/library/domain/library_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => LibraryMode.debugSet(null));

  group('LibraryMode.detect', () {
    test('is on when the page names its settings', () {
      LibraryMode.detect(() => 'library.json');

      expect(LibraryMode.isOn, isTrue);
      expect(LibraryMode.settingsPath, 'library.json');
    });

    test('is off when the page has no tag', () {
      LibraryMode.detect(() => null);

      expect(LibraryMode.isOn, isFalse);
      expect(LibraryMode.settingsPath, isNull);
    });
  });

  group('parseLibraryMetaContent', () {
    test('accepts a plain relative path, trimmed', () {
      expect(parseLibraryMetaContent(' library.json '), 'library.json');
      expect(parseLibraryMetaContent('settings/library.json'),
          'settings/library.json');
    });

    for (final content in [
      null,
      '',
      '   ',
      'https://evil.example/library.json',
      '//evil.example/library.json',
      '/library.json',
      '../library.json',
      'a/../library.json',
      './library.json',
      'library.json?x=1',
      'library.json#x',
      'javascript:alert(1)',
      'a//library.json',
    ]) {
      test('switches library mode off for "$content"', () {
        expect(parseLibraryMetaContent(content), isNull);
      });
    }
  });
}
