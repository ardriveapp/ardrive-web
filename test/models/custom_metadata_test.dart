import 'package:ardrive/models/custom_metadata_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CustomMetadata class', () {
    test('can hold null values', () {
      final customMetadata = CustomMetadata(null);
      final customMetadataAsJson = CustomMetadata.toJson(customMetadata);
      expect(customMetadata, isNotNull);
      expect(customMetadataAsJson, isNull);
    });

    test('can hold empty values', () {
      final customMetadata = CustomMetadata({});
      final customMetadataAsJson = CustomMetadata.toJson(customMetadata);
      expect(customMetadata, isNotNull);
      expect(customMetadataAsJson, isNotNull);
      expect(customMetadataAsJson, isEmpty);
    });

    test('can hold non-empty values', () {
      final customMetadata = CustomMetadata({'Custom-Key': 'Custom-Value'});
      final customMetadataAsJson = CustomMetadata.toJson(customMetadata);
      expect(customMetadata, isNotNull);
      expect(customMetadataAsJson, isNotNull);
      expect(customMetadataAsJson, isNotEmpty);
    });

    test('can be created from JSON', () {
      final customMetadata =
          CustomMetadata.fromJson({'Custom-Key': 'Custom-Value'});
      expect(customMetadata, isNotNull);
      expect(customMetadata, isNotEmpty);
    });

    test('can be created from null JSON', () {
      final customMetadata = CustomMetadata.fromJson(null);
      expect(customMetadata, isNull);
    });

    test('can be created from empty JSON', () {
      final customMetadata = CustomMetadata.fromJson({});
      expect(customMetadata, isNotNull);
      expect(customMetadata, isEmpty);
    });
  });
}
