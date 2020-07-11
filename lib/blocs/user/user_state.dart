part of 'user_bloc.dart';

@immutable
abstract class UserState {}

class UserLoading extends UserState {}

class UserAuthenticated extends UserState {
  final Wallet userWallet;

  UserAuthenticated({this.userWallet});
}

class UserAuthenticating extends UserState {}

class UserUnauthenticated extends UserState {}
