part of 'profile_cubit.dart';

@immutable
abstract class ProfileState extends Equatable {
  @override
  List<Object> get props => [];
}

class ProfileLoading extends ProfileState {}

class ProfileLoaded extends ProfileState {
  final String username;
  final String password;
  final Wallet wallet;
  final SecretKey cipherKey;

  ProfileLoaded({this.username, this.password, this.wallet, this.cipherKey});

  @override
  List<Object> get props => [username, password, wallet, cipherKey];
}

class ProfileUnavailable extends ProfileState {}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfilePromptUnlock extends ProfileUnavailable {}
