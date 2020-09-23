part of 'profile_bloc.dart';

@immutable
abstract class ProfileState {}

class ProfileActivating extends ProfileState {}

class ProfileActive extends ProfileState {
  final String username;
  final String password;
  final Wallet wallet;
  final CipherKey cipherKey;

  ProfileActive({this.username, this.password, this.wallet, this.cipherKey});
}

class ProfileInactive extends ProfileState {}
