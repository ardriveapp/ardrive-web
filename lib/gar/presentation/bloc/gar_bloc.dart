import 'package:ardrive/gar/domain/repositories/gar_repository.dart';
import 'package:ardrive/gar/utils/gateway_validator.dart';
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

    on<ValidateCustomGateway>((event, emit) async {
      emit(ValidatingCustomGateway(event.gatewayUrl));
      
      try {
        final validationResult = await garRepository.validateCustomGateway(event.gatewayUrl);
        emit(CustomGatewayValidated(
          gatewayUrl: event.gatewayUrl,
          validationResult: validationResult,
        ));
      } catch (e) {
        emit(CustomGatewayValidated(
          gatewayUrl: event.gatewayUrl,
          validationResult: GatewayValidationResult(
            isValid: false,
            isActive: false,
            isArweaveGateway: false,
            message: 'Error validating gateway: ${e.toString()}',
          ),
        ));
      }
    });

    on<SelectCustomGateway>((event, emit) async {
      emit(VerifyingGateway());
      
      try {
        final validationResult = await garRepository.validateCustomGateway(event.gatewayUrl);
        
        if (validationResult.canBeUsed) {
          emit(CustomGatewaySelected(event.gatewayUrl));
        } else {
          emit(const GatewayIsInactive());
        }
      } catch (e) {
        emit(const GatewayIsInactive());
      }
    });

    on<ClearCustomGatewayValidation>((event, emit) {
      final currentState = state;
      
      if (currentState is GatewaysLoaded) {
        emit(
          GatewaysLoaded(
            gateways: currentState.gateways,
            currentGateway: currentState.currentGateway,
            searchResults: currentState.searchResults,
          ),
        );
      }
    });

    on<ConfirmCustomGatewayChange>((event, emit) async {
      try {
        await garRepository.updateCustomGateway(event.gatewayUrl);
        
        // Create a custom gateway object for the success state
        final customGateway = Gateway(
          operatorStake: 0,
          gatewayAddress: 'custom',
          observerAddress: 'custom',
          settings: Settings(
            port: 443,
            protocol: 'https',
            allowDelegatedStaking: false,
            fqdn: Uri.parse(garRepository.cleanGatewayUrl(event.gatewayUrl)).host,
            delegateRewardShareRatio: 0,
            properties: 'custom',
            note: 'Custom gateway',
            minDelegatedStake: 0,
            label: GatewayValidator.generateLabel(event.gatewayUrl),
            autoStake: false,
          ),
          startTimestamp: DateTime.now().millisecondsSinceEpoch,
          totalDelegatedStake: 0,
          stats: Stats(
            failedConsecutiveEpochs: 0,
            observedEpochCount: 0,
            passedConsecutiveEpochs: 0,
            totalEpochCount: 0,
            prescribedEpochCount: 0,
            passedEpochCount: 0,
            failedEpochCount: 0,
          ),
          status: 'custom',
        );
        
        emit(GatewayChanged(customGateway));
      } catch (e) {
        emit(const GatewaysError());
      }
    });
  }
}
