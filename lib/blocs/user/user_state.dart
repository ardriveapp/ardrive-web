part of 'user_bloc.dart';

@immutable
abstract class UserState {}

class UserAuthenticating extends UserState {}

class UserAuthenticated extends UserState {
  final Wallet userWallet;

  UserAuthenticated({this.userWallet});
}

class UserUnauthenticated extends UserState {}
