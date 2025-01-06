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

  group('isValidUuidFormat Tests', () {
    test('Valid UUID format', () {
      expect(isValidUuidFormat('123e4567-e89b-12d3-a456-426614174000'), isTrue);
    });

    test('Invalid UUID format - missing parts', () {
      expect(isValidUuidFormat('123e4567-e89b-12d3-a456'), isFalse);
    });

    test('Invalid UUID format - extra parts', () {
      expect(isValidUuidFormat('123e4567-e89b-12d3-a456-426614174000-1234'),
          isFalse);
    });

    test('Invalid UUID format - wrong separator', () {
      expect(
          isValidUuidFormat('123e4567:e89b:12d3:a456:426614174000'), isFalse);
    });

    test('Invalid UUID format - invalid characters', () {
      expect(
          isValidUuidFormat('123e4567-e89b-12d3-a456-42661417g000'), isFalse);
    });

    test('Invalid UUID format - wrong length', () {
      expect(isValidUuidFormat('123e4567-e89b-12d3-a456-42661417400'), isFalse);
    });

    test('Invalid UUID format - empty string', () {
      expect(isValidUuidFormat(''), isFalse);
    });
  });

  group('isValidArweaveTxId Tests', () {
    test('should return true for valid Arweave transaction IDs', () {
      expect(isValidArweaveTxId('mn8q_r4h8i7oZaVDnpusJ6uOGIVH1Ak80ZBhy8sUc7w'),
          isTrue);

      expect(isValidArweaveTxId('cQU3_wXscrghGlqmbF5ef-iu9tOdFq2Xuq-anLRIAHA'),
          isTrue);
      expect(isValidArweaveTxId('2FivxlgSuK9s2GZ0cvAYkQTc0ZrmEZLPhwBmVtY_bVY'),
          isTrue);
    });

    test('should return false for invalid length', () {
      expect(isValidArweaveTxId('abc'), isFalse); // Too short
      expect(
          isValidArweaveTxId('_R4bUV8qt7UYsBAGJHmXwKpKP2qJuwWGPOfnQYRXVIw123'),
          isFalse); // Too long
      expect(isValidArweaveTxId(''), isFalse); // Empty string
    });

    test('should return false for invalid characters', () {
      expect(isValidArweaveTxId('_R4bUV8qt7UYsB@GJHmXwKpKP2qJuwWGPOfnQYRXVIw'),
          isFalse); // Contains @
      expect(isValidArweaveTxId('_R4bUV8qt7UYsB#GJHmXwKpKP2qJuwWGPOfnQYRXVIw'),
          isFalse); // Contains #
      expect(isValidArweaveTxId('_R4bUV8qt7UYsB GJHmXwKpKP2qJuwWGPOfnQYRXVIw'),
          isFalse); // Contains space
    });

    test('should return false for invalid base64url encoding', () {
      // Contains invalid padding character '='
      expect(isValidArweaveTxId('_R4bUV8qt7UYsBAGJHmXwKpKP2qJuwWGPOfnQYRXVI='),
          isFalse);
      // Contains '/' which is not base64url safe
      expect(isValidArweaveTxId('_R4bUV8qt7/YsBAGJHmXwKpKP2qJuwWGPOfnQYRXVIw'),
          isFalse);
      // Contains '+' which is not base64url safe
      expect(isValidArweaveTxId('_R4bUV8qt7+YsBAGJHmXwKpKP2qJuwWGPOfnQYRXVIw'),
          isFalse);
    });
  });
}
