import 'package:ardrive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'gar_event.dart';
part 'gar_state.dart';

class GarBloc extends Bloc<GarEvent, GarState> {
  final ConfigService configService;
  final ArweaveService arweave;

  GarBloc({
    required this.configService,
    required this.arweave,
  }) : super(GarInitial()) {
    on<GarEvent>((event, emit) {
      if (event is UpdateArweaveGatewayUrl) {
        configService.updateAppConfig(
          configService.config.copyWith(
            defaultArweaveGatewayUrl: event.arweaveGatewayUrl,
          ),
        );

        arweave.setGatewayUrl(Uri.parse(event.arweaveGatewayUrl));

        emit(GatewayChanged());
      }
    });
  }
}
