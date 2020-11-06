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

  /// The user's wallet balance in winston.
  final BigInt walletBalance;

  final SecretKey cipherKey;

  ProfileLoaded({
    @required this.username,
    @required this.password,
    @required this.wallet,
    @required this.walletBalance,
    @required this.cipherKey,
  });

  ProfileLoaded copyWith({
    String username,
    String password,
    Wallet wallet,
    BigInt walletBalance,
    SecretKey cipherKey,
  }) =>
      ProfileLoaded(
        username: username ?? this.username,
        password: password ?? this.password,
        wallet: wallet ?? this.wallet,
        walletBalance: walletBalance ?? this.walletBalance,
        cipherKey: cipherKey ?? this.cipherKey,
      );

  @override
  List<Object> get props => [username, password, wallet, cipherKey];
}

class ProfileUnavailable extends ProfileState {}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfilePromptUnlock extends ProfileUnavailable {}
