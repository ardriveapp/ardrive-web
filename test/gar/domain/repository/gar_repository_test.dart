import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockArioSDK extends Mock implements ArioSDK {}

class MockConfigService extends Mock implements ConfigService {}

class MockArweaveService extends Mock implements ArweaveService {}

class MockGateway extends Mock implements Gateway {}

class MockConfig extends Mock implements AppConfig {}

class MockSettings extends Mock implements Settings {}

void main() {
  late GarRepositoryImpl repository;
  late MockArioSDK arioSDK;
  late MockConfigService configService;
  late MockArweaveService arweaveService;

  setUp(() {
    arioSDK = MockArioSDK();
    configService = MockConfigService();
    arweaveService = MockArweaveService();
    repository = GarRepositoryImpl(
      arioSDK: arioSDK,
      configService: configService,
      arweave: arweaveService,
    );
  });

  setUpAll(() {
    registerFallbackValue(AppConfig(
      allowedDataItemSizeForTurbo: 1,
      stripePublishableKey: '',
      defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
    ));
  });

  group('GarRepositoryImpl', () {
    test('getGateways fetches and returns gateways', () async {
      final gateways = [MockGateway()];
      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);

      final result = await repository.getGateways();

      expect(result, equals(gateways));
      verify(() => arioSDK.getGateways()).called(1);
    });

    test('getSelectedGateway returns the correct gateway', () async {
      final gateway = MockGateway();
      final gateways = [gateway];

      final settings = MockSettings();

      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: '',
        defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
      ));
      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);
      when(() => gateway.settings).thenReturn(settings);
      when(() => settings.fqdn).thenReturn('current.gateway.com');

      // Manually populate the _gateways list for this test
      await repository.getGateways();

      final selectedGateway = repository.getSelectedGateway();

      expect(selectedGateway, equals(gateway));
    });

    test(
        'updateGateway updates the config and sets the gateway in ArweaveService',
        () {
      final gateway = MockGateway();
      final settings = MockSettings();
      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: '',
        defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
      ));
      when(() => gateway.settings).thenReturn(settings);
      when(() => settings.fqdn).thenReturn('new.gateway.com');

      repository.updateGateway(gateway);

      verify(() => configService.updateAppConfig(any())).called(1);
      verify(() => arweaveService.setGateway(gateway)).called(1);
    });

    test('searchGateways returns gateways matching the query', () async {
      final gateway1 = MockGateway();
      final gateway2 = MockGateway();

      final gateways = [gateway1, gateway2];

      final settings1 = MockSettings();
      final settings2 = MockSettings();

      when(() => gateway1.settings).thenReturn(settings1);
      when(() => gateway2.settings).thenReturn(settings2);

      when(() => settings1.fqdn).thenReturn('first.gateway.com');
      when(() => settings2.fqdn).thenReturn('second.gateway.com');

      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);

      // Manually populate the _gateways list
      await repository.getGateways();

      final results = repository.searchGateways('first');

      expect(results, equals([gateway1]));
    });

    test(
        'searchGateways returns an empty list when no gateways match the query',
        () {
      final gateway1 = MockGateway();
      final gateway2 = MockGateway();

      final gateways = [gateway1, gateway2];

      final settings1 = MockSettings();
      final settings2 = MockSettings();

      when(() => gateway1.settings).thenReturn(settings1);
      when(() => gateway2.settings).thenReturn(settings2);

      when(() => settings1.fqdn).thenReturn('first.gateway.com');
      when(() => settings2.fqdn).thenReturn('second.gateway.com');

      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);
      final results = repository.searchGateways('nonexistent');

      expect(results, isEmpty);
    });
  });
}
