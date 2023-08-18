import 'package:ardrive/utils/custom_metadata.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCustomJsonMetadata methdo', () {
    test('should return null if customJsonMetadata is null', () {
      final result = parseCustomJsonMetadata(null);
      expect(result, null);
    });

    test('should return parsed json if customJsonMetadata is valid', () {
      final result = parseCustomJsonMetadata('{"key": "value"}');
      expect(result, {'key': 'value'});
    });
  });

  group('parseCustomGqlTags methdo', () {
    test('should return null if customGQLTags is null', () {
      final result = parseCustomGqlTags(null);
      expect(result, null);
    });

    test('should return parsed json if customGQLTags is valid', () {
      final result =
          parseCustomGqlTags('[{"name": "tag1", "value": "value1"}]');
      expect(result, [
        Tag('tag1', 'value1'),
      ]);
    });
  });
}
