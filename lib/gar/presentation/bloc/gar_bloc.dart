import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:collection/collection.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'gar_event.dart';
part 'gar_state.dart';

class GarBloc extends Bloc<GarEvent, GarState> {
  final ConfigService configService;
  final ArweaveService arweave;
  final ArioSDK arioSDK;

  GarBloc({
    required this.configService,
    required this.arweave,
    required this.arioSDK,
  }) : super(GarInitial()) {
    on<GetGateways>((event, emit) async {
      emit(LoadingGateways());

      final gateways = await arioSDK.getGateways();

      final currentGatewayUrl = configService.config.defaultArweaveGatewayUrl;
      final currentGatewayDomain = Uri.parse(currentGatewayUrl!).host;

      final currentGateway = gateways.firstWhereOrNull(
        (gateway) => gateway.settings.fqdn == currentGatewayDomain,
      );

      emit(GatewaysLoaded(gateways: gateways, currentGateway: currentGateway));
    });

    on<GarEvent>((event, emit) {
      if (event is UpdateArweaveGatewayUrl) {
        configService.updateAppConfig(
          configService.config.copyWith(
            defaultArweaveGatewayUrl: 'https://${event.gateway.settings.fqdn}',
          ),
        );

        arweave.setGatewayUrl(
          Uri.parse(
            'https://${event.gateway.settings.fqdn}',
          ),
        );

        emit(GatewayChanged(event.gateway));
      }
    });

    on<SearchGateways>((event, emit) {
      final currentState = state;

      if (currentState is GatewaysLoaded) {
        final searchResults = currentState.gateways.where(
          (gateway) => gateway.settings.fqdn.contains(event.query),
        );

        logger.d('Search results: $searchResults');

        emit(currentState.copyWith(searchResults: searchResults.toList()));
      }
    });

    on<CleanSearchResults>((event, emit) {
      final currentState = state;

      if (currentState is GatewaysLoaded) {
        emit(GatewaysLoaded(
            gateways: currentState.gateways,
            currentGateway: currentState.currentGateway));
      }
    });
  }
}
