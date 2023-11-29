import 'package:ardrive/blocs/upload/limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getBundleUploadSizeLimit Tests', () {
    test(
        'should return turboWebPlatformsBundleSizeLimit when isTurbo is true and platform is Web',
        () {
      // Call the function with isTurbo = true and mockKIsWeb = true
      final result = getBundleUploadSizeLimit(true, mockKIsWeb: true);

      // Assert that the result matches the expected value
      expect(result, equals(turboWebPlatformsBundleSizeLimit));
    });

    test(
        'should return turboBundleSizeLimit when isTurbo is true and platform is not Web',
        () {
      // Call the function with isTurbo = true and mockKIsWeb = false
      final result = getBundleUploadSizeLimit(true, mockKIsWeb: false);

      // Assert that the result matches the expected value
      expect(result, equals(turboBundleSizeLimit));
    });

    test('should return d2nBundleSizeLimit when isTurbo is false', () {
      // Test for both Web and non-Web platforms since it should not matter in this case

      // Call the function with isTurbo = false and mockKIsWeb = true
      expect(getBundleUploadSizeLimit(false, mockKIsWeb: true),
          equals(d2nBundleSizeLimit));

      // Call the function with isTurbo = false and mockKIsWeb = false
      expect(getBundleUploadSizeLimit(false, mockKIsWeb: false),
          equals(d2nBundleSizeLimit));
    });
  });
}
