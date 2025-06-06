part of 'gar_bloc.dart';

abstract class GarEvent extends Equatable {
  const GarEvent();

  @override
  List<Object> get props => [];
}

final class GetGateways extends GarEvent {}

final class SelectGateway extends GarEvent {
  final Gateway gateway;

  const SelectGateway({
    required this.gateway,
  });

  @override
  List<Object> get props => [gateway];
}

final class ConfirmGatewayChange extends GarEvent {
  final Gateway gateway;

  const ConfirmGatewayChange({
    required this.gateway,
  });
}

final class SearchGateways extends GarEvent {
  final String query;

  const SearchGateways({
    required this.query,
  });

  @override
  List<Object> get props => [query];
}

final class CleanSearchResults extends GarEvent {}
