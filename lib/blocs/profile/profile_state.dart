part of 'profile_cubit.dart';

@immutable
abstract class ProfileState extends Equatable {
  @override
  List<Object> get props => [];
}

/// [ProfileCheckingAvailability] indicates that whether or not the user
/// has a profile is unknown and is being checked.
class ProfileCheckingAvailability extends ProfileState {}

/// [ProfileUnavailable] is a superclass state that indicates that
/// the user has a profile that can/has been logged into.
abstract class ProfileAvailable extends ProfileState {}

/// [ProfileUnavailable] is a superclass state that indicates that
/// the user no profile that can/has been logged into.
abstract class ProfileUnavailable extends ProfileState {}

class ProfilePromptLogIn extends ProfileAvailable {}

class ProfileLoggingIn extends ProfileAvailable {}

class ProfileLoggedIn extends ProfileAvailable {
  final String username;
  final String password;

  final Wallet wallet;

  /// The user's wallet balance in winston.
  final BigInt walletBalance;

  final SecretKey cipherKey;

  ProfileLoggedIn({
    @required this.username,
    @required this.password,
    @required this.wallet,
    @required this.walletBalance,
    @required this.cipherKey,
  });

  ProfileLoggedIn copyWith({
    String username,
    String password,
    Wallet wallet,
    BigInt walletBalance,
    SecretKey cipherKey,
  }) =>
      ProfileLoggedIn(
        username: username ?? this.username,
        password: password ?? this.password,
        wallet: wallet ?? this.wallet,
        walletBalance: walletBalance ?? this.walletBalance,
        cipherKey: cipherKey ?? this.cipherKey,
      );

  @override
  List<Object> get props => [username, password, wallet, cipherKey];
}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfileLoggingOut extends ProfileUnavailable {}
