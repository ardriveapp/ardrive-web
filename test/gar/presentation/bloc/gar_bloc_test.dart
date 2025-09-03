import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/presentation/bloc/gar_bloc.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGarRepository extends Mock implements GarRepository {}

class MockGateway extends Mock implements Gateway {}

void main() {
  late GarBloc garBloc;
  late MockGarRepository garRepository;

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
    garRepository = MockGarRepository();
    garBloc = GarBloc(garRepository: garRepository);
  });

  tearDown(() {
    garBloc.close();
  });

  test('initial state is GarInitial', () {
    expect(garBloc.state, equals(GarInitial()));
  });

  blocTest<GarBloc, GarState>(
    'emits [LoadingGateways, GatewaysLoaded] when GetGateways is added',
    build: () {
      final gateways = [MockGateway()];
      when(() => garRepository.getGateways()).thenAnswer((_) async => gateways);
      when(() => garRepository.getSelectedGateway())
          .thenAnswer((_) async => MockGateway());
      return garBloc;
    },
    act: (bloc) => bloc.add(GetGateways()),
    expect: () => [
      LoadingGateways(),
      isA<GatewaysLoaded>(),
    ],
    verify: (_) {
      verify(() => garRepository.getGateways()).called(1);
      verify(() => garRepository.getSelectedGateway()).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits [GatewaysError] when GetGateways fails',
    build: () {
      when(() => garRepository.getGateways()).thenThrow(Exception());
      return garBloc;
    },
    act: (bloc) => bloc.add(GetGateways()),
    expect: () => [
      LoadingGateways(),
      isA<GatewaysError>(),
    ],
    verify: (_) {
      verify(() => garRepository.getGateways()).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits [VerifyingGateway, GatewayActive] when SelectGateway is added and gateway is active',
    build: () {
      when(() => garRepository.updateGateway(gateway))
          .thenAnswer((_) async => {});
      when(() => garRepository.isGatewayActive(gateway))
          .thenAnswer((_) async => true);
      return garBloc;
    },
    act: (bloc) => bloc.add(SelectGateway(gateway: gateway)),
    expect: () => [
      isA<VerifyingGateway>(),
      isA<GatewayActive>(),
    ],
    verify: (_) {
      verify(() => garRepository.isGatewayActive(gateway)).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits [VerifyingGateway, GatewayIsInactive] when SelectGateway is added and gateway is inactive',
    build: () {
      when(() => garRepository.isGatewayActive(gateway))
          .thenAnswer((_) async => false);
      return garBloc;
    },
    act: (bloc) => bloc.add(SelectGateway(gateway: gateway)),
    expect: () => [
      isA<VerifyingGateway>(),
      isA<GatewayIsInactive>(),
    ],
    verify: (_) {
      verify(() => garRepository.isGatewayActive(gateway)).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits [GatewayChanged] when ConfirmGatewayChange is added',
    build: () {
      when(() => garRepository.updateGateway(gateway))
          .thenAnswer((_) async => {});
      return garBloc;
    },
    act: (bloc) => bloc.add(ConfirmGatewayChange(gateway: gateway)),
    expect: () => [
      isA<GatewayChanged>(),
    ],
    verify: (_) {
      verify(() => garRepository.updateGateway(gateway)).called(1);
    },
  );

  blocTest<GarBloc, GarState>(
    'emits updated GatewaysLoaded with search results when SearchGateways is added',
    build: () {
      final gateways = [MockGateway()];
      when(() => garRepository.searchGateways('test')).thenReturn(gateways);
      return garBloc;
    },
    seed: () => GatewaysLoaded(gateways: [MockGateway()]),
    act: (bloc) => bloc.add(const SearchGateways(query: 'test')),
    expect: () => [
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
