part of 'user_balance_bloc.dart';

sealed class UserBalanceState extends Equatable {
  const UserBalanceState();

  @override
  List<Object> get props => [];
}

final class UserBalanceInitial extends UserBalanceState {}

final class UserBalanceLoaded extends UserBalanceState {
  final BigInt arBalance;
  final String? ioTokens;
  final bool errorFetchingIOTokens;

  const UserBalanceLoaded({
    required this.arBalance,
    required this.ioTokens,
    required this.errorFetchingIOTokens,
  });
}

final class UserBalanceLoadingIOTokens extends UserBalanceLoaded {
  const UserBalanceLoadingIOTokens({
    required super.arBalance,
    super.ioTokens,
    super.errorFetchingIOTokens = false,
  });
}
