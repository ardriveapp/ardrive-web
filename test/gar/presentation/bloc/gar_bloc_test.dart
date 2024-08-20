import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

class MockArioSDK extends Mock implements ArioSDK {}

class MockGateway extends Mock implements Gateway {}

class MockSettings extends Mock implements Settings {}

void main() {
  late GarBloc garBloc;
  late MockConfigService configService;
  late MockArweaveService arweaveService;
  late MockArioSDK arioSDK;

  final settings = Settings(
    protocol: 'http',
    fqdn: '192.168.1.1',
    port: 80,
    allowDelegatedStaking: true,
    delegateRewardShareRatio: 50,
    properties: 'some properties',
    note: 'some note',
    minDelegatedStake: 500,
    label: '',
    autoStake: false,
  );

  final gateway = Gateway(
    settings: settings,
    gatewayAddress: 'gatewayAddress',
    observerAddress: 'observerAddress',
    operatorStake: 1000,
    startTimestamp: 1622519735,
    endTimestamp: 1622529735,
    totalDelegatedStake: 2000,
    stats: Stats(
      failedConsecutiveEpochs: 1,
      observedEpochCount: 10,
      passedConsecutiveEpochs: 5,
      totalEpochCount: 20,
      prescribedEpochCount: 15,
      passedEpochCount: 15,
      failedEpochCount: 5,
    ),
    status: 'active',
  );

  setUp(() {
    configService = MockConfigService();
    arweaveService = MockArweaveService();
    arioSDK = MockArioSDK();
    garBloc = GarBloc(
      configService: configService,
      arweave: arweaveService,
      arioSDK: arioSDK,
    );

    when(() => configService.config.defaultArweaveGatewayUrl)
        .thenReturn('https://current.gateway.com');
  });

  setUpAll(() {
    registerFallbackValue(AppConfig(
      allowedDataItemSizeForTurbo: 1,
      stripePublishableKey: '',
      defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
    ));

    registerFallbackValue(gateway);
  });

  tearDown(() {
    garBloc.close();
  });

  test('initial state is GarInitial', () {
    expect(garBloc.state, equals(GarInitial()));
  });

  blocTest<GarBloc, GarState>(
    'emits [LoadingGateways, GatewaysLoaded] when GetGateways is added',
    setUp: () {},
    build: () {
      final gateway = MockGateway();
      final settings = MockSettings();

      final gateways = [gateway];
      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);
      when(() => gateway.settings).thenReturn(settings);
      when(() => settings.fqdn).thenReturn('test.com');

      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: '',
        defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
      ));

      return GarBloc(
        configService: configService,
        arweave: arweaveService,
        arioSDK: arioSDK,
      );
    },
    act: (bloc) => bloc.add(GetGateways()),
    expect: () => [
      LoadingGateways(),
      isA<GatewaysLoaded>(),
    ],
    verify: (_) {
      verify(() => arioSDK.getGateways()).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits [GatewayChanged] when UpdateArweaveGatewayUrl is added',
    build: () {
      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: '',
        defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
      ));

      when(() => configService.updateAppConfig(any())).thenReturn(null);
      when(() => arweaveService.setGateway(any())).thenReturn(null);
      return garBloc;
    },
    act: (bloc) {
      bloc.add(UpdateArweaveGatewayUrl(gateway: gateway));
    },
    expect: () => [
      isA<GatewayChanged>(),
    ],
    verify: (_) {
      verify(() => configService.updateAppConfig(any())).called(1);
      verify(() => arweaveService.setGateway(any())).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits updated GatewaysLoaded with search results when SearchGateways is added',
    build: () {
      final gateway = MockGateway();
      final settings = MockSettings();

      final gateways = [gateway];
      when(() => arioSDK.getGateways()).thenAnswer((_) async => gateways);
      when(() => gateway.settings).thenReturn(settings);
      when(() => settings.fqdn).thenReturn('test.com');

      when(() => configService.config).thenReturn(AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: '',
        defaultArweaveGatewayForDataRequest: 'https://current.gateway.com',
      ));

      return GarBloc(
        configService: configService,
        arweave: arweaveService,
        arioSDK: arioSDK,
      );
    },
    seed: () => GatewaysLoaded(gateways: [MockGateway()]),
    act: (bloc) {
      bloc.add(GetGateways());
      bloc.add(const SearchGateways(query: 'test'));
    },
    expect: () => [
      isA<LoadingGateways>(),
      isA<GatewaysLoaded>(),
      isA<GatewaysLoaded>()
          .having((state) => state.searchResults, 'searchResults', isNotEmpty),
    ],
  );

  blocTest<GarBloc, GarState>(
    'emits original GatewaysLoaded without search results when CleanSearchResults is added',
    build: () {
      return garBloc;
    },
    seed: () => GatewaysLoaded(
        gateways: [MockGateway()], searchResults: [MockGateway()]),
    act: (bloc) => bloc.add(CleanSearchResults()),
    expect: () => [
      isA<GatewaysLoaded>()
          .having((state) => state.searchResults, 'searchResults', isNull),
    ],
  );
}
