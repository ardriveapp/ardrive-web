import 'package:ardrive/utils/opaque_error_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isOpaqueErrorText', () {
    test('is true for what a release build prints for an exception', () {
      expect(isOpaqueErrorText("Instance of 'minified:Xy'"), isTrue);
      expect(isOpaqueErrorText('minified:Ab'), isTrue);
      expect(isOpaqueErrorText("Exception: Instance of 'minified:Xy'"), isTrue);
      expect(isOpaqueErrorText("Instance of '_Opaque'"), isTrue);
    });

    test('is false when anything around the opaque part can be read', () {
      expect(isOpaqueErrorText('My drive: minified:Ab'), isFalse);
      expect(isOpaqueErrorText('My drive: Unknown error'), isFalse);
      expect(isOpaqueErrorText('Gateway timeout (504)'), isFalse);
      expect(isOpaqueErrorText('Exception: the gateway said no'), isFalse);
    });
  });

  group('withoutOpaqueParts', () {
    test('keeps the readable rest, such as a drive name', () {
      expect(withoutOpaqueParts('My drive: minified:Ab'),
          'My drive: Unknown error');
      expect(withoutOpaqueParts("Failed: Instance of 'minified:Xy'"),
          'Failed: Unknown error');
    });

    test('leaves a readable message as it is', () {
      expect(withoutOpaqueParts('Bad gateway (502)'), 'Bad gateway (502)');
    });
  });
}
