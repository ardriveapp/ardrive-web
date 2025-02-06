import 'package:ardrive/utils/is_supported_image_type_for_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isSupportedImageTypeForPreview', () {
    test('returns true for supported image types', () {
      expect(isSupportedImageTypeForPreview('image/jpeg'), isTrue);
      expect(isSupportedImageTypeForPreview('image/png'), isTrue);
      expect(isSupportedImageTypeForPreview('image/gif'), isTrue);
      expect(isSupportedImageTypeForPreview('image/webp'), isTrue);
      expect(isSupportedImageTypeForPreview('image/bmp'), isTrue);
    });

    test('returns false for unsupported image types', () {
      expect(isSupportedImageTypeForPreview('image/'), isFalse);
      expect(isSupportedImageTypeForPreview('application/pdf'), isFalse);
      expect(isSupportedImageTypeForPreview('image/tiff'), isFalse);
    });

    test('returns false for null input', () {
      expect(isSupportedImageTypeForPreview(null), isFalse);
    });
  });
}
