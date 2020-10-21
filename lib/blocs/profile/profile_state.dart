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

  ProfileLoaded({
    @required this.username,
    @required this.password,
    @required this.wallet,
    @required this.cipherKey,
  });

  @override
  List<Object> get props => [username, password, wallet, cipherKey];
}

class ProfileUnavailable extends ProfileState {}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfilePromptUnlock extends ProfileUnavailable {}
