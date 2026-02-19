import 'package:ardrive/arns/utils/arns_address_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('getAddressesFromArns', () {
    test('returns correct addresses with domain and undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
        undername: 'test',
      );

      expect(httpAddress, 'https://test_example.ar.io');
      expect(arAddress, 'ar://test_example');
    });

    test('returns correct addresses with domain only', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
      );

      expect(httpAddress, 'https://example.ar.io');
      expect(arAddress, 'ar://example');
    });

    test('returns correct addresses with @ undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
        undername: '@',
      );

      expect(httpAddress, 'https://example.ar.io');
      expect(arAddress, 'ar://example');
    });

    test('returns correct addresses with empty string undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
        undername: '',
      );

      expect(httpAddress, 'https://example.ar.io');
      expect(arAddress, 'ar://example');
    });

    test('handles special characters in domain and undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example-domain',
        undername: 'test_undername',
      );

      expect(httpAddress, 'https://test_undername_example-domain.ar.io');
      expect(arAddress, 'ar://test_undername_example-domain');
    });
  });
}
