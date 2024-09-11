part of 'user_balance_bloc.dart';

sealed class UserBalanceEvent extends Equatable {
  const UserBalanceEvent();

  @override
  List<Object> get props => [];
}

final class GetUserBalance extends UserBalanceEvent {}

final class RefreshUserBalance extends UserBalanceEvent {}
