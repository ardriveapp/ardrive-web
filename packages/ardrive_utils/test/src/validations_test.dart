import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidUuidV4 Tests', () {
    test('should return true for a valid UUID v4', () {
      expect(isValidUuidV4('d96fed74-7908-4810-9e0a-fc2754e4c810'), isTrue);
      expect(isValidUuidV4('2da64b48-bc4b-41e4-9b23-f937a2bb0397'), isTrue);
      expect(isValidUuidV4('f47ac10b-58cc-4372-a567-0e02b2c3d479'), isTrue);
    });

    test('should return false for an invalid UUID format', () {
      expect(isValidUuidV4('invalid-uuid'), isFalse);

      /// without the dashes
      expect(isValidUuidV4('123e4567e89b-12d3-a456-426614174000'), isFalse);
      expect(isValidUuidV4('123e4567e89b12d3-a456-426614174000'), isFalse);
      expect(isValidUuidV4('123e4567e89b12d3a456-426614174000'), isFalse);
      expect(isValidUuidV4('123e4567e89b12d3a456426614174000'), isFalse);
      expect(
          isValidUuidV4('12345678-1234-1234-1234-1234567890ab-1234'), isFalse);
      expect(isValidUuidV4('123456781234123412341234567890ab'), isFalse);
    });

    test('should return false for an empty string', () {
      expect(isValidUuidV4(''), isFalse);
    });

    test('should handle case sensitivity', () {
      expect(isValidUuidV4('123E4567-E89B-42D3-A456-426614174000'), isTrue);
      expect(isValidUuidV4('123e4567-e89b-42d3-a456-426614174000'), isTrue);
    });

    // Boundary Values Tests
    test('Boundary Value: Minimum', () {
      expect(isValidUuidV4('00000000-0000-4000-8000-000000000000'), isTrue);
    });

    test('Boundary Value: Maximum', () {
      expect(isValidUuidV4('ffffffff-ffff-4fff-bfff-ffffffffffff'), isTrue);
    });

    // wrong version
    test('Boundary Value: Minimum', () {
      expect(isValidUuidV4('00000000-0000-5000-8000-000000000000'), isFalse);
      expect(isValidUuidV4('00000000-0000-3000-8000-000000000000'), isFalse);
      expect(isValidUuidV4('00000000-0000-2000-8000-000000000000'), isFalse);
      expect(isValidUuidV4('00000000-0000-1000-8000-000000000000'), isFalse);
    });
    test('Boundary Value: Maximum', () {
      expect(isValidUuidV4('ffffffff-ffff-5fff-bfff-ffffffffffff'), isFalse);
      expect(isValidUuidV4('ffffffff-ffff-3fff-bfff-ffffffffffff'), isFalse);
      expect(isValidUuidV4('ffffffff-ffff-2fff-bfff-ffffffffffff'), isFalse);
      expect(isValidUuidV4('ffffffff-ffff-1fff-bfff-ffffffffffff'), isFalse);
    });
  });
}
