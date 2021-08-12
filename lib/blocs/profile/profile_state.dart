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
  final String? username;
  final String password;

  final Wallet? wallet;

  final String walletAddress;

  /// The user's wallet balance in winston.
  final BigInt walletBalance;

  final SecretKey? cipherKey;

  ProfileLoggedIn({
    required this.username,
    required this.password,
    required this.wallet,
    required this.walletAddress,
    required this.walletBalance,
    required this.cipherKey,
  });

  ProfileLoggedIn copyWith({
    String? username,
    String? password,
    Wallet? wallet,
    String? walletAddress,
    BigInt? walletBalance,
    SecretKey? cipherKey,
  }) =>
      ProfileLoggedIn(
        username: username ?? this.username,
        password: password ?? this.password,
        wallet: wallet ?? this.wallet,
        walletAddress: walletAddress ?? this.walletAddress,
        walletBalance: walletBalance ?? this.walletBalance,
        cipherKey: cipherKey ?? this.cipherKey,
      );

  @override
  List<Object?> get props => [
        username,
        password,
        wallet,
        walletAddress,
        walletBalance,
        cipherKey,
      ];

  Future<Uint8List> getRawWalletSignature(Uint8List signatureData) {
    return wallet == null
        ? arconnect.getSignature(signatureData)
        : wallet!.sign(signatureData);
  }

  Future<String> getWalletOwner() {
    return wallet == null ? arconnect.getPublicKey() : wallet!.getOwner();
  }

  Future<String> getWalletAddress() {
    return wallet == null ? arconnect.getWalletAddress() : wallet!.getAddress();
  }
}

class ProfilePromptAdd extends ProfileUnavailable {}

class ProfileLoggingOut extends ProfileUnavailable {}
