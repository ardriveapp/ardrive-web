part of 'gar_bloc.dart';

abstract class GarEvent extends Equatable {
  const GarEvent();

  @override
  List<Object> get props => [];
}

final class UpdateArweaveGatewayUrl extends GarEvent {
  final String arweaveGatewayUrl;

  const UpdateArweaveGatewayUrl({
    required this.arweaveGatewayUrl,
  });

  @override
  List<Object> get props => [arweaveGatewayUrl];
}
