part of 'login_bloc.dart';

abstract class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object?> get props => [];
}

class LoginLanding extends LoginState {
  const LoginLanding();
}

class LoginInitial extends LoginState {
  final bool isArConnectAvailable;
  final bool existingUserFlow;

  const LoginInitial(
      {required this.isArConnectAvailable, required this.existingUserFlow});

  @override
  List<Object> get props => [isArConnectAvailable, existingUserFlow];
}

class LoginLoading extends LoginState {}

/// The sign-in panel asks for a recovery phrase, or a keyfile instead.
class LoginEnterRecoveryPhrase extends LoginState {
  const LoginEnterRecoveryPhrase();
}

/// The browser wallets the Log in panel offers.
enum BrowserWallet { wander, metamask, phantom, solflare, otherSolana }

/// What a browser wallet has been asked for.
enum BrowserWalletRequest { connect, signIn }

/// A browser wallet has been asked to connect or sign, and its answer is
/// awaited. The sign-in panel says where to approve it and offers Cancel.
class LoginWaitingOnWallet extends LoginState {
  const LoginWaitingOnWallet({
    required this.wallet,
    this.request = BrowserWalletRequest.connect,
  });

  final BrowserWallet wallet;
  final BrowserWalletRequest request;

  @override
  List<Object?> get props => [wallet, request];
}

class LoginLoadingIfUserAlreadyExists extends LoginState {}

class LoginLoadingIfUserAlreadyExistsSuccess extends LoginState {}

class LoginShowLoader extends LoginState {}

/// A new account's key is being made on this device, which can take up to a
/// minute. Shown in the sign-in panel rather than over it.
class LoginCreatingAccount extends LoginState {
  const LoginCreatingAccount({this.noWalletFound = false});

  /// Sign up found no wallet extension to offer, so it went straight here,
  /// and the panel says so.
  final bool noWalletFound;

  @override
  List<Object?> get props => [noWalletFound];
}

class LoginShowBlockingDialog extends LoginState {
  const LoginShowBlockingDialog({required this.message});

  final String message;
}

class LoginCloseBlockingDialog extends LoginState {}

class PromptPassword extends LoginState {
  const PromptPassword({
    this.mnemonic,
    this.wallet,
    this.derivedEthWallet,
    this.sourceWalletAddress,
    this.alreadyLoggedIn = false,
    this.showWalletCreated = false,
    this.isPasswordInvalid = false,
    this.hasGraphQLException = false,
  });

  final String? mnemonic;
  final Wallet? wallet;
  final EthereumProviderWallet? derivedEthWallet;

  /// The source wallet address (Solana/Ethereum) for display purposes.
  final String? sourceWalletAddress;
  final bool alreadyLoggedIn;
  final bool isPasswordInvalid;
  final bool hasGraphQLException;

  /// Used to determine next screens to show on password success
  final bool showWalletCreated;

  @override
  List<Object?> get props => [
        mnemonic,
        wallet,
        showWalletCreated,
        isPasswordInvalid,
        hasGraphQLException,
      ];
}

class CreateNewPassword extends LoginState {
  const CreateNewPassword(
      {required this.wallet,
      this.derivedEthWallet,
      this.sourceWalletAddress,
      this.mnemonic,
      required this.isNewUser,
      required this.showWalletCreated,
      this.fromSignUp = false,
      this.retrying = false});

  final String? mnemonic;
  final Wallet wallet;

  /// A browser wallet chosen from Sign up's choice: a new ArDrive account,
  /// so its password follows the new-account rules.
  final bool fromSignUp;

  /// Asked again because the last try could not finish.
  final bool retrying;
  final EthereumProviderWallet? derivedEthWallet;

  /// The source wallet address (Solana/Ethereum) for display purposes.
  final String? sourceWalletAddress;

  /// Used to determine next screens to show on password success
  final bool isNewUser;
  final bool showWalletCreated;

  @override
  List<Object?> get props =>
      [mnemonic, wallet, isNewUser, showWalletCreated, fromSignUp, retrying];
}

class LoginFailure extends LoginState {
  const LoginFailure(this.error);

  final Object error;
}

class LoginUnknownFailure extends LoginState {
  const LoginUnknownFailure(this.error);

  final Object error;
}

class GatewayLoginFailure extends LoginState {
  const GatewayLoginFailure(this.error, this.gatewayUrl);

  final String gatewayUrl;

  final Object error;
}

class LoginSuccess extends LoginState {
  const LoginSuccess(this.user);
  final User user;
}

class LoginDownloadGeneratedWallet extends LoginState {
  const LoginDownloadGeneratedWallet({this.mnemonic, required this.wallet});
  final String? mnemonic;
  final Wallet wallet;
}

class LoginCheckingPassword extends LoginState {}

class LoginPasswordFailed extends LoginState {}

class LoginPasswordFailedWithPrivateDriveNotFound extends LoginState {}

class LoginCreatePasswordComplete extends LoginState {}
