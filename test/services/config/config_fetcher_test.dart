import 'dart:convert';

import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_fetcher.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLocalKeyValueStore extends Mock implements LocalKeyValueStore {}

class MockAssetBundle extends Mock implements AssetBundle {}

void main() {
  late MockLocalKeyValueStore localStore;
  late MockAssetBundle assetBundle;
  late ConfigFetcher configFetcher;

  setUp(() {
    localStore = MockLocalKeyValueStore();
    assetBundle = MockAssetBundle();

    configFetcher = ConfigFetcher(localStore: localStore);

    TestWidgetsFlutterBinding.ensureInitialized();

    // Inject mock asset bundle for all tests
    configFetcher.assetBundle = assetBundle;
  });

  group('fetchConfig', () {
    final newConfig = AppConfig(
      configVersion: 2,
      stripePublishableKey: 'new-key',
      allowedDataItemSizeForTurbo: 200,
      defaultArweaveGatewayUrl: 'new-gateway',
      defaultArweaveGatewayForDataRequest: const SelectedGateway(
        label: 'new',
        url: 'new',
      ),
    );
    final newConfigString = json.encode(newConfig.toJson());

    test('returns config from local storage if present and up-to-date',
        () async {
      // Arrange
      final storedConfig = AppConfig(
        configVersion: 2,
        stripePublishableKey: 'stored-key',
        allowedDataItemSizeForTurbo: 100,
        defaultArweaveGatewayUrl: 'stored-gateway',
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'stored',
          url: 'stored',
        ),
      );
      final storedConfigString = json.encode(storedConfig.toJson());

      when(() => localStore.getString('config')).thenReturn(storedConfigString);
      when(() => assetBundle.loadString(any()))
          .thenAnswer((_) async => newConfigString);

      // Act
      final result = await configFetcher.fetchConfig(Flavor.development);

      // Assert
      expect(result.configVersion, 2);
      expect(result.stripePublishableKey, 'stored-key');
      verifyNever(() => localStore.putString(any(), any()));
    });

    test('loads config from assets and saves to local storage if not present',
        () async {
      // Arrange
      when(() => localStore.getString('config')).thenReturn(null);
      when(() => assetBundle.loadString(any()))
          .thenAnswer((_) async => newConfigString);
      when(() => localStore.putString('config', any()))
          .thenAnswer((_) async => true);

      // Act
      final result = await configFetcher.fetchConfig(Flavor.development);

      // Assert
      expect(result.configVersion, 2);
      expect(result.stripePublishableKey, 'new-key');
      verify(() => localStore.putString('config', newConfigString)).called(1);
    });

    test('replaces local config with asset config if local version is older',
        () async {
      // Arrange
      final oldConfig = AppConfig(
        configVersion: 1,
        stripePublishableKey: 'old-key',
        allowedDataItemSizeForTurbo: 100,
        defaultArweaveGatewayUrl: 'old-gateway',
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'old',
          url: 'old',
        ),
      );
      final oldConfigString = json.encode(oldConfig.toJson());

      when(() => localStore.getString('config')).thenReturn(oldConfigString);
      when(() => assetBundle.loadString(any()))
          .thenAnswer((_) async => newConfigString);
      when(() => localStore.putString('config', any()))
          .thenAnswer((_) async => true);

      // Act
      final result = await configFetcher.fetchConfig(Flavor.development);

      // Assert
      expect(result.configVersion, 2);
      expect(result.stripePublishableKey, 'new-key');
      verify(() => localStore.putString('config', newConfigString)).called(1);
    });

    test(
        'replaces local config with asset config if local config has no version',
        () async {
      // Arrange
      final oldConfig = AppConfig(
        // No configVersion
        stripePublishableKey: 'old-key',
        allowedDataItemSizeForTurbo: 100,
        defaultArweaveGatewayUrl: 'old-gateway',
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'old',
          url: 'old',
        ),
      );
      final oldConfigString = json.encode(oldConfig.toJson());

      when(() => localStore.getString('config')).thenReturn(oldConfigString);
      when(() => assetBundle.loadString(any()))
          .thenAnswer((_) async => newConfigString);
      when(() => localStore.putString('config', any()))
          .thenAnswer((_) async => true);

      // Act
      final result = await configFetcher.fetchConfig(Flavor.development);

      // Assert
      expect(result.configVersion, 2);
      expect(result.stripePublishableKey, 'new-key');
      verify(() => localStore.putString('config', newConfigString)).called(1);
    });

    test('replaces local config with asset config if local config is malformed',
        () async {
      // Arrange
      when(() => localStore.getString('config')).thenReturn('{invalid-json');
      when(() => assetBundle.loadString(any()))
          .thenAnswer((_) async => newConfigString);
      when(() => localStore.putString('config', any()))
          .thenAnswer((_) async => true);

      // Act
      final result = await configFetcher.fetchConfig(Flavor.development);

      // Assert
      expect(result.configVersion, 2);
      expect(result.stripePublishableKey, 'new-key');
      verify(() => localStore.putString('config', newConfigString)).called(1);
    });
  });

  group('saveConfigOnDevToolsPrefs', () {
    test('saves the config to local storage', () async {
      final config = AppConfig(
        configVersion: 2,
        stripePublishableKey: 'key',
        defaultArweaveGatewayUrl: 'url',
        allowedDataItemSizeForTurbo: 100,
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'Arweave.net',
          url: 'https://arweave.net',
        ),
      );

      when(() => localStore.putString('config', any()))
          .thenAnswer((i) => Future.value(true));

      await configFetcher.saveConfigOnDevToolsPrefs(config);

      verify(() => localStore.putString('config', json.encode(config.toJson())))
          .called(1);
    });
  });

  group('resetDevToolsPrefs', () {
    test('removes the config from local storage', () async {
      when(() => localStore.remove('config'))
          .thenAnswer((i) => Future.value(true));

      await configFetcher.resetDevToolsPrefs();

      verify(() => localStore.remove('config')).called(1);
    });
  });
}
