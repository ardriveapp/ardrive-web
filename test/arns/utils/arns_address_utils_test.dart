import 'package:ardrive/arns/utils/arns_address_utils.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../gar/domain/repository/gar_repository_test.dart';

void main() {
  final configService = MockConfigService();

  group('getAddressesFromArns', () {
    setUp(() {
      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 1000,
        stripePublishableKey: 'test',
      ));
    });

    test('returns correct addresses with domain and undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
        undername: 'test',
        configService: configService,
      );

      expect(httpAddress, 'https://test_example.ardrive.net');
      expect(arAddress, 'ar://test_example.ardrive.net');
    });

    test('returns correct addresses with domain only', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
        configService: configService,
      );

      expect(httpAddress, 'https://example.ardrive.net');
      expect(arAddress, 'ar://example.ardrive.net');
    });

    test('returns correct addresses with @ undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example',
        undername: '@',
        configService: configService,
      );

      expect(httpAddress, 'https://example.ardrive.net');
      expect(arAddress, 'ar://example.ardrive.net');
    });

    test('handles special characters in domain and undername', () {
      final (httpAddress, arAddress) = getAddressesFromArns(
        domain: 'example-domain',
        undername: 'test_undername',
        configService: configService,
      );

      expect(httpAddress, 'https://test_undername_example-domain.ardrive.net');
      expect(arAddress, 'ar://test_undername_example-domain.ardrive.net');
    });
  });
}
