import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

void main() {
  late ConfigService configService;
  late MockConfigFetcher mockConfigFetcher;
  late MockAppFlavors mockAppFlavors;

  setUp(() {
    mockConfigFetcher = MockConfigFetcher();
    mockAppFlavors = MockAppFlavors();
    configService = ConfigService(
        configFetcher: mockConfigFetcher, appFlavors: mockAppFlavors);

    registerFallbackValue(Flavor.production);
    registerFallbackValue(Flavor.development);
  });

  group('loadConfig', () {
    test('loads config from ConfigFetcher', () async {
      when(() => mockAppFlavors.getAppFlavor())
          .thenAnswer((_) async => Flavor.production);
      when(() => mockConfigFetcher.fetchConfig(any())).thenAnswer(
        (_) async => AppConfig(
          stripePublishableKey: '',
          allowedDataItemSizeForTurbo: 100,
          defaultArweaveGatewayForDataRequest: const SelectedGateway(
            label: 'ArDrive Turbo Gateway',
            url: 'https://ardrive.net',
          ),
        ),
      );

      await configService.loadConfig();

      verify(() => mockConfigFetcher.fetchConfig(any())).called(1);
    });
  });

  group('getAppFlavor', () {
    test('returns the app flavor from AppFlavors', () async {
      when(() => mockAppFlavors.getAppFlavor())
          .thenAnswer((_) async => Flavor.production);

      final result = await configService.loadAppFlavor();

      expect(result, equals(Flavor.production));
    });

    test('returns the app flavor from AppFlavors', () async {
      when(() => mockAppFlavors.getAppFlavor())
          .thenAnswer((_) async => Flavor.development);

      final result = await configService.loadAppFlavor();

      expect(result, equals(Flavor.development));
    });

    test('returns production flavor when exception is thrown', () async {
      when(() => mockAppFlavors.getAppFlavor()).thenThrow(Exception());

      final result = await configService.loadAppFlavor();

      expect(result, equals(Flavor.production));
    });
  });

  group('updateAppConfig', () {
    test('saves the config to ConfigFetcher and updates local config', () {
      final config = AppConfig(
        stripePublishableKey: '',
        allowedDataItemSizeForTurbo: 100,
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'ArDrive Turbo Gateway',
          url: 'https://ardrive.net',
        ),
      );

      configService.updateAppConfig(config);

      verify(() => mockConfigFetcher.saveConfigOnDevToolsPrefs(config))
          .called(1);

      expect(configService.config, equals(config));
    });
  });

  group('resetDevToolsPrefs', () {
    test('resets config in ConfigFetcher and loads config', () async {
      when(() => mockAppFlavors.getAppFlavor())
          .thenAnswer((_) async => Flavor.production);
      when(() => mockConfigFetcher.fetchConfig(any()))
          .thenAnswer((_) async => AppConfig(
                stripePublishableKey: '',
                allowedDataItemSizeForTurbo: 100,
                defaultArweaveGatewayForDataRequest: const SelectedGateway(
                  label: 'ArDrive Turbo Gateway',
                  url: 'https://ardrive.net',
                ),
              ));

      await configService.resetDevToolsPrefs();

      verify(() => mockConfigFetcher.resetDevToolsPrefs()).called(1);
      verify(() => mockConfigFetcher.fetchConfig(any())).called(1);
    });
  });

  group('config', () {
    test('throws an Exception when _config is null', () {
      expect(() => configService.config, throwsA(isA<Exception>()));
    });

    test('returns the expected AppConfig when _config is not null', () async {
      when(() => mockAppFlavors.getAppFlavor())
          .thenAnswer((_) async => Flavor.production);
      when(() => mockConfigFetcher.fetchConfig(any()))
          .thenAnswer((_) async => AppConfig(
                stripePublishableKey: '',
                allowedDataItemSizeForTurbo: 100,
                defaultArweaveGatewayForDataRequest: const SelectedGateway(
                  label: 'ArDrive Turbo Gateway',
                  url: 'https://ardrive.net',
                ),
              ));

      await configService.loadConfig();

      expect(configService.config, isInstanceOf<AppConfig>());
    });
  });
  group('flavor', () {
    test('throws an Exception when _flavor is null', () {
      expect(() => configService.flavor, throwsA(isA<Exception>()));
    });

    test('returns the expected Flavor when _flavor is not null', () async {
      when(() => mockAppFlavors.getAppFlavor())
          .thenAnswer((_) async => Flavor.production);
      when(() => mockConfigFetcher.fetchConfig(any()))
          .thenAnswer((_) async => AppConfig(
                allowedDataItemSizeForTurbo: 100,
                stripePublishableKey: '',
                defaultArweaveGatewayForDataRequest: const SelectedGateway(
                  label: 'ArDrive Turbo Gateway',
                  url: 'https://ardrive.net',
                ),
              ));

      await configService.loadConfig(); // Assuming this sets _flavor

      expect(configService.flavor, equals(Flavor.production));
    });
  });
}
