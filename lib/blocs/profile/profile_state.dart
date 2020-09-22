part of 'profile_bloc.dart';

@immutable
abstract class ProfileState {}

class UserAuthenticating extends ProfileState {}

class ProfileActive extends ProfileState {
  final Wallet userWallet;

  ProfileActive({this.userWallet});
}

class ProfileInactive extends ProfileState {}
