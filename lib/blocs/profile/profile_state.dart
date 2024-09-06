part of 'profile_cubit.dart';

@immutable
abstract class ProfileState extends Equatable {
  @override
  List<Object?> get props => [];
}

/// [ProfileCheckingAvailability] indicates that whether or not the user
/// has a profile is unknown and is being checked.
class ProfileCheckingAvailability extends ProfileState {}

/// [ProfileUnavailable] is a superclass state that indicates that
/// the user has a profile that can/has been logged into.
abstract class ProfileAvailable extends ProfileState {}

/// [ProfileUnavailable] is a superclass state that indicates that
/// the user has no profile to log into.
abstract class ProfileUnavailable extends ProfileState {}

class ProfilePromptLogIn extends ProfileAvailable {}

class ProfileLoggingIn extends ProfileAvailable {}

class ProfileLoggedIn extends ProfileAvailable {
  final User user;
  final bool useTurbo;
  final arconnect = ArConnectService();

  ProfileLoggedIn({
    required this.user,
    required this.useTurbo,
  });

  ProfileLoggedIn copyWith({
    User? user,
    bool? useTurbo,
  }) =>
      ProfileLoggedIn(
        user: user ?? this.user,
        useTurbo: useTurbo ?? this.useTurbo,
      );

  bool hasMinimumBalanceForUpload({required BigInt minimumWalletBalance}) =>
      user.walletBalance > minimumWalletBalance;

  bool canUpload({required BigInt minimumWalletBalance}) =>
      hasMinimumBalanceForUpload(minimumWalletBalance: minimumWalletBalance) ||
      useTurbo;

  @override
  List<Object?> get props => [user];
}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfileLoggingOut extends ProfileUnavailable {}
