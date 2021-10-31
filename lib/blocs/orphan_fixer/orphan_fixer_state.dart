part of 'orphan_fixer_cubit.dart';

@immutable
abstract class OrphanFixerState extends Equatable {
  @override
  List<Object> get props => [];
}

class OrphanFixerInitial extends OrphanFixerState {}

class OrphanFixerInProgress extends OrphanFixerState {}

class OrphanFixerSuccess extends OrphanFixerState {}

class OrphanFixerFailure extends OrphanFixerState {}

class OrphanFixerWalletMismatch extends OrphanFixerState {}
