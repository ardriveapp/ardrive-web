part of 'gar_bloc.dart';

abstract class GarState extends Equatable {
  const GarState();

  @override
  List<Object?> get props => [];
}

class GarInitial extends GarState {}

class GatewayChanged extends GarState {
  @override
  List<Object> get props => [];

  final Gateway gateway;

  const GatewayChanged(this.gateway);
}

class LoadingGateways extends GarState {}

class GatewaysLoaded extends GarState {
  final List<Gateway> gateways;
  final List<Gateway>? searchResults;
  final Gateway? currentGateway;

  const GatewaysLoaded({
    required this.gateways,
    this.searchResults,
    this.currentGateway,
  });

  @override
  List<Object?> get props => [gateways, searchResults, currentGateway];

  GatewaysLoaded copyWith({
    List<Gateway>? gateways,
    List<Gateway>? searchResults,
    Gateway? currentGateway,
  }) {
    return GatewaysLoaded(
      gateways: gateways ?? this.gateways,
      searchResults: searchResults ?? this.searchResults,
      currentGateway: currentGateway ?? this.currentGateway,
    );
  }
}
