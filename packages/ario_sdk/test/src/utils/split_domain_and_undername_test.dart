import 'package:ario_sdk/src/utils/split_domain_and_undername.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractNameAndDomain', () {
    test('should correctly split input with underscore', () {
      final result = extractNameAndDomain('example_domain');
      expect(result, equals({'name': 'example', 'domain': 'domain'}));
    });

    test('should handle input without underscore', () {
      final result = extractNameAndDomain('domain');
      expect(result, equals({'name': null, 'domain': 'domain'}));
    });

    test('should handle input with multiple underscores', () {
      final result = extractNameAndDomain('example_with_multiple_domain');
      expect(result,
          equals({'name': 'example_with_multiple', 'domain': 'domain'}));
    });

    test('should handle empty input', () {
      final result = extractNameAndDomain('');
      expect(result, equals({'name': null, 'domain': ''}));
    });

    test('should handle input with only underscore', () {
      final result = extractNameAndDomain('_');
      expect(result, equals({'name': '', 'domain': ''}));
    });
  });
}
