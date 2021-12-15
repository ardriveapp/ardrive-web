part of 'ghost_fixer_cubit.dart';

@immutable
abstract class GhostFixerState extends Equatable {
  @override
  List<Object> get props => [];
}

class GhostFixerInitial extends GhostFixerState {}

class GhostFixerInProgress extends GhostFixerState {}

class GhostFixerSuccess extends GhostFixerState {}

class GhostFixerFailure extends GhostFixerState {}

class GhostFixerWalletMismatch extends GhostFixerState {}