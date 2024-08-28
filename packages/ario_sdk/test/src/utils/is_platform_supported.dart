import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isArioSDKSupportedOnPlatform', () {
    test('returns true for Web platform', () {
      // Arrange
      AppPlatform.setMockPlatform(platform: SystemPlatform.Web);

      // Act
      final result = isArioSDKSupportedOnPlatform();

      // Assert
      expect(result, isTrue);
    });

    test('returns false for Android platform', () {
      // Arrange
      AppPlatform.setMockPlatform(platform: SystemPlatform.Android);

      // Act
      final result = isArioSDKSupportedOnPlatform();

      // Assert
      expect(result, isFalse);
    });

    test('returns false for iOS platform', () {
      // Arrange
      AppPlatform.setMockPlatform(platform: SystemPlatform.iOS);

      // Act
      final result = isArioSDKSupportedOnPlatform();

      // Assert
      expect(result, isFalse);
    });

    test('returns false for unknown platform', () {
      // Arrange
      AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

      // Act
      final result = isArioSDKSupportedOnPlatform();

      // Assert
      expect(result, isFalse);
    });
  });
}
