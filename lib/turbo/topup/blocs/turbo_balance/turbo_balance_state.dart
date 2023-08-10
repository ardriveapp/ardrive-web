part of 'turbo_balance_cubit.dart';

@immutable
abstract class TurboBalanceState extends Equatable {
  const TurboBalanceState();

  @override
  List<Object?> get props => [];
}

class TurboBalanceInitial extends TurboBalanceState {}

class TurboBalanceLoading extends TurboBalanceState {}

class NewTurboUserState extends TurboBalanceState {}

class TurboBalanceSuccessState extends TurboBalanceState {
  final BigInt balance;

  const TurboBalanceSuccessState({
    required this.balance,
  });

  @override
  List<Object?> get props => [balance];
}

class TurboBalanceErrorState extends TurboBalanceState {}
