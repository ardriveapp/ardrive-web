part of 'profile_bloc.dart';

@immutable
abstract class ProfileState {}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final String username;
  final String password;
  final Wallet wallet;
  final SecretKey cipherKey;

  ProfileLoaded({this.username, this.password, this.wallet, this.cipherKey});
}

class ProfileUnavailable extends ProfileState {}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfilePromptUnlock extends ProfileUnavailable {}
