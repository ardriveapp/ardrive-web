import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'gar_event.dart';
part 'gar_state.dart';

class GarBloc extends Bloc<GarEvent, GarState> {
  final GarRepository garRepository;

  GarBloc({
    required this.garRepository,
  }) : super(GarInitial()) {
    on<GetGateways>((event, emit) async {
      try {
        emit(LoadingGateways());

        final gateways = await garRepository.getGateways();
        final currentGateway = await garRepository.getSelectedGateway();

        emit(
          GatewaysLoaded(
            gateways: gateways,
            currentGateway: currentGateway,
          ),
        );
      } catch (e) {
        emit(const GatewaysError());
      }
    });

    on<SelectGateway>((event, emit) async {
      emit(VerifyingGateway());

      final isGatewayActive =
          await garRepository.isGatewayActive(event.gateway);

      if (isGatewayActive) {
        emit(GatewayActive(event.gateway));
      } else {
        emit(const GatewayIsInactive());
      }
    });

    on<ConfirmGatewayChange>((event, emit) {
      garRepository.updateGateway(event.gateway);

      emit(GatewayChanged(event.gateway));
    });

    on<SearchGateways>((event, emit) {
      final currentState = state;

      if (currentState is GatewaysLoaded) {
        final searchResults = garRepository.searchGateways(event.query);

        emit(currentState.copyWith(searchResults: searchResults.toList()));
      }
    });

    on<CleanSearchResults>((event, emit) {
      final currentState = state;

      if (currentState is GatewaysLoaded) {
        emit(
          GatewaysLoaded(
            gateways: currentState.gateways,
            currentGateway: currentState.currentGateway,
          ),
        );
      }
    });
  }
}
