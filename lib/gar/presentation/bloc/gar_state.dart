part of 'gar_bloc.dart';

abstract class GarState extends Equatable {
  const GarState();

  @override
  List<Object> get props => [];
}

class GarInitial extends GarState {}

class GatewayChanged extends GarState {
  @override
  List<Object> get props => [];
}
