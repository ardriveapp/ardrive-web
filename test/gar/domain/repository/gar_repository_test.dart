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
      final gateway3 = MockGateway();

      final gateways = [gateway1, gateway2, gateway3];

      final settings1 = MockSettings();
      final settings2 = MockSettings();
      final settings3 = MockSettings();

      when(() => gateway1.settings).thenReturn(settings1);
      when(() => gateway2.settings).thenReturn(settings2);
      when(() => gateway3.settings).thenReturn(settings3);

      when(() => settings1.fqdn).thenReturn('first.gateway.com');
      when(() => settings2.fqdn).thenReturn('second.gateway.com');
      when(() => settings3.fqdn).thenReturn('third.gateway.com');
      // now search for labels
      when(() => settings1.label).thenReturn('first gateway');
      when(() => settings2.label).thenReturn('second gateway');
      when(() => settings3.label).thenReturn('first');

      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);

      // Manually populate the _gateways list
      await repository.getGateways();

      final results = repository.searchGateways('first');

      ///  The search for 'first' returns two gateways:
      ///  1. gateway1: matches because its FQDN is 'first.gateway.com'
      ///  2. gateway3: matches because its label is 'first'
      ///
      ///  The search is case-insensitive and matches partial strings in both
      ///  the FQDN and the label of the gateway settings.

      expect(results, equals([gateway1, gateway3]));
    });

    test('searchGateways returns gateways matching the query only in labels',
        () async {
      final gateway1 = MockGateway();
      final gateway2 = MockGateway();
      final gateway3 = MockGateway();

      final gateways = [gateway1, gateway2, gateway3];

      final settings1 = MockSettings();
      final settings2 = MockSettings();
      final settings3 = MockSettings();

      when(() => gateway1.settings).thenReturn(settings1);
      when(() => gateway2.settings).thenReturn(settings2);
      when(() => gateway3.settings).thenReturn(settings3);

      when(() => settings1.fqdn).thenReturn('first.gateway.com');
      when(() => settings2.fqdn).thenReturn('second.gateway.com');
      when(() => settings3.fqdn).thenReturn('third.gateway.com');

      when(() => settings1.label).thenReturn('Alpha Gateway');
      when(() => settings2.label).thenReturn('Beta Gateway');
      when(() => settings3.label).thenReturn('Gamma Gateway');

      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);

      // Manually populate the _gateways list
      await repository.getGateways();

      final results = repository.searchGateways('gateway');

      // The search for 'gateway' returns all three gateways because it matches their labels,
      // even though it doesn't match any of their FQDNs.
      expect(results, equals([gateway1, gateway2, gateway3]));

      // Verify that the search is case-insensitive
      final caseInsensitiveResults = repository.searchGateways('GaTewAy');
      expect(caseInsensitiveResults, equals([gateway1, gateway2, gateway3]));
    });

    test(
        'searchGateways returns an empty list when no gateways match the query',
        () {
      final gateway1 = MockGateway();
      final gateway2 = MockGateway();
      final gateway3 = MockGateway();

      final gateways = [gateway1, gateway2, gateway3];

      final settings1 = MockSettings();
      final settings2 = MockSettings();
      final settings3 = MockSettings();

      when(() => gateway1.settings).thenReturn(settings1);
      when(() => gateway2.settings).thenReturn(settings2);
      when(() => gateway3.settings).thenReturn(settings3);
      when(() => settings1.fqdn).thenReturn('first.gateway.com');
      when(() => settings2.fqdn).thenReturn('second.gateway.com');
      when(() => settings3.fqdn).thenReturn('third.gateway.com');

      // labels
      when(() => settings1.label).thenReturn('first gateway');
      when(() => settings2.label).thenReturn('second gateway');
      when(() => settings3.label).thenReturn('third gateway');

      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);

      final results = repository.searchGateways('nonexistent');

      expect(results, isEmpty);
    });
  });
}
