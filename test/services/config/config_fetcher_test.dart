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
  });

  final configStringDev = json.encode(AppConfig(
    allowedDataItemSizeForTurbo: 100,
    stripePublishableKey: 'stripeKey',
    defaultArweaveGatewayUrl: 'devGatewayUrl',
    defaultArweaveGatewayForDataRequest: const SelectedGateway(
      label: 'ArDrive Turbo Gateway',
      url: 'https://ardrive.net',
    ),
  )..toJson());

  group('fetchConfig', () {
    test('returns the dev config when flavor is dev', () async {
      when(() => localStore.getString('config')).thenReturn(configStringDev);

      final result = await configFetcher.fetchConfig(Flavor.development);

      expect(result, isInstanceOf<AppConfig>());
      expect(result.defaultArweaveGatewayUrl, equals('devGatewayUrl'));
      expect(
          result.defaultArweaveGatewayForDataRequest,
          equals(const SelectedGateway(
            label: 'ArDrive Turbo Gateway',
            url: 'https://ardrive.net',
          )));
    });

    test('returns the staging config when flavor is staging', () async {
      final configStringStaging = json.encode(AppConfig(
        allowedDataItemSizeForTurbo: 100,
        stripePublishableKey: 'stripeKey',
        defaultArweaveGatewayUrl: 'stagingGatewayUrl',
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'ArDrive Turbo Gateway',
          url: 'https://ardrive.net',
        ),
      )..toJson());

      when(() => localStore.getString('config'))
          .thenReturn(configStringStaging);

      final result = await configFetcher.fetchConfig(Flavor.staging);

      expect(result, isInstanceOf<AppConfig>());
      expect(result.defaultArweaveGatewayUrl, equals('stagingGatewayUrl'));
      expect(
          result.defaultArweaveGatewayForDataRequest,
          equals(const SelectedGateway(
            label: 'ArDrive Turbo Gateway',
            url: 'https://ardrive.net',
          )));
    });
    test(
        'returns the dev config when flavor is dev from env when there is no previous dev config saved on dev tools',
        () async {
      when(() => localStore.getString('config')).thenReturn(null);

      // loads the real file
      when(() => assetBundle.loadString('assets/config/dev.json'))
          .thenAnswer((_) async => '');

      when(() => localStore.putString('config', any()))
          .thenAnswer((i) => Future.value(true));

      final result = await configFetcher.fetchConfig(Flavor.development);

      expect(result, isInstanceOf<AppConfig>());
      expect(result.defaultArweaveGatewayUrl, equals('https://ardrive.net'));
      expect(
          result.defaultArweaveGatewayForDataRequest,
          equals(const SelectedGateway(
            label: 'ArDrive Turbo Gateway',
            url: 'https://ardrive.net',
          )));
    });
  });

  group('loadFromDevToolsPrefs', () {
    test('returns config from local storage if present', () async {
      when(() => localStore.getString('config')).thenReturn(configStringDev);

      final result =
          await configFetcher.loadFromLocalSettings(Flavor.development);

      expect(result, isInstanceOf<AppConfig>());
      expect(result.defaultArweaveGatewayUrl, equals('devGatewayUrl'));
    });

    test('loads config from env and saves to local storage if not present',
        () async {
      when(() => localStore.getString('config')).thenReturn(null);
      when(() => localStore.getString('arweaveGatewayUrl'))
          .thenReturn('gatewayUrl');
      when(() => localStore.getBool('enableQuickSyncAuthoring'))
          .thenReturn(true);
      when(() => assetBundle.loadString('assets/config/dev.json'))
          .thenAnswer((_) async => '{}');
      when(() => localStore.putString('config', any()))
          .thenAnswer((i) => Future.value(true));

      final result =
          await configFetcher.loadFromLocalSettings(Flavor.development);

      expect(result, isInstanceOf<AppConfig>());
      expect(result.defaultArweaveGatewayUrl, equals('gatewayUrl'));
      verify(() => localStore.putString('config', any())).called(1);
    });

    test(
        'loads config from env and saves to local storage if loading from dev tools throws',
        () async {
      when(() => localStore.getString('config')).thenThrow(Exception());
      when(() => localStore.getString('arweaveGatewayUrl'))
          .thenReturn('gatewayUrl');
      when(() => localStore.getBool('enableQuickSyncAuthoring'))
          .thenReturn(true);
      when(() => assetBundle.loadString('assets/config/dev.json'))
          .thenAnswer((_) async => '{}');
      when(() => localStore.putString('config', any()))
          .thenAnswer((i) => Future.value(true));

      final result =
          await configFetcher.loadFromLocalSettings(Flavor.development);

      expect(result, isInstanceOf<AppConfig>());
      expect(result.defaultArweaveGatewayUrl, equals('gatewayUrl'));
      verify(() => localStore.putString('config', any())).called(1);
    });
  });

  group('saveConfigOnDevToolsPrefs', () {
    test('saves the config to local storage', () {
      final config = AppConfig(
        stripePublishableKey: '',
        defaultArweaveGatewayUrl: '',
        allowedDataItemSizeForTurbo: 100,
        defaultArweaveGatewayForDataRequest: const SelectedGateway(
          label: 'ArDrive Turbo Gateway',
          url: 'https://ardrive.net',
        ),
      );

      when(() => localStore.putString('config', any()))
          .thenAnswer((i) => Future.value(true));

      configFetcher.saveConfigOnDevToolsPrefs(config);

      verify(() => localStore.putString('config', json.encode(config.toJson())))
          .called(1);
    });
  });

  group('resetDevToolsPrefs', () {
    test('removes the config from local storage', () {
      when(() => localStore.remove('config'))
          .thenAnswer((i) => Future.value(true));

      configFetcher.resetDevToolsPrefs();

      verify(() => localStore.remove('config')).called(1);
    });
  });
}
