import 'package:ardrive/utils/is_supported_image_type_for_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSupportedImageTypeForPreview', () {
    test('returns true for supported image types', () {
      expect(isSupportedImageTypeForPreview('image/jpeg'), isTrue);
      expect(isSupportedImageTypeForPreview('image/png'), isTrue);
      expect(isSupportedImageTypeForPreview('image/gif'), isTrue);
    });

    test('returns false for unsupported image types', () {
      expect(isSupportedImageTypeForPreview('image/bmp'), isFalse);
      expect(isSupportedImageTypeForPreview('application/pdf'), isFalse);
    });

    test('returns false for null input', () {
      expect(isSupportedImageTypeForPreview(null), isFalse);
    });
  });
}
