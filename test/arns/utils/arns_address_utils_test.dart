import 'package:ardrive/arns/utils/arns_address_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getAddressesFromArns', () {
    test('returns correct addresses with domain and undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example.com',
        undername: 'test',
      );

      expect(httpAddress, 'https://test_example.com.ar-io.dev');
      expect(arAddress, 'ar://test_example.com');
    });

    test('returns correct addresses with domain only', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example.com',
      );

      expect(httpAddress, 'https://example.com.ar-io.dev');
      expect(arAddress, 'ar://example.com');
    });

    test('returns correct addresses with @ undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example.com',
        undername: '@',
      );

      expect(httpAddress, 'https://example.com.ar-io.dev');
      expect(arAddress, 'ar://example.com');
    });

    test('handles special characters in domain and undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example-domain.com',
        undername: 'test_undername',
      );

      expect(
          httpAddress, 'https://test_undername_example-domain.com.ar-io.dev');
      expect(arAddress, 'ar://test_undername_example-domain.com');
    });
  });
}
