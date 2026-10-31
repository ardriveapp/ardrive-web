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
enum BrowserWalletRequest {
  connect,
  signIn,

  /// The one approval that opens the saved account and the drives this
  /// device remembers.
  openDrives,
}

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
  const LoginCreatingAccount();
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
    this.noAccountFound = false,
  });

  /// The password typed for a MetaMask with no record found opened no
  /// ArDrive account.
  final bool noAccountFound;

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
        noAccountFound,
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

/// The account on this device was saved by a newer ArDrive than this tab
/// runs. Reloading gets the newer build. Nothing may offer to sign out or
/// forget the account from here.
class LoginProfileFromNewerVersion extends LoginState {
  const LoginProfileFromNewerVersion();
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

/// The sign-in password opened none of the wallet's private drives. The user
/// tries again ([RetrySignInPassword]) or continues with those drives locked
/// ([ContinueSignInWithLockedDrives]).
class LoginPasswordOpensNoDrives extends LoginState {
  const LoginPasswordOpensNoDrives();
}

/// Back at the password after [LoginPasswordOpensNoDrives], with what was
/// typed selected.
class LoginPasswordRetry extends LoginState {
  const LoginPasswordRetry();
}

class LoginPasswordFailedWithPrivateDriveNotFound extends LoginState {}

class LoginCreatePasswordComplete extends LoginState {}

/// Why Welcome back's approval didn't open the account.
enum WalletUnlockProblem {
  /// The person said no in the wallet, or it didn't answer.
  declined,

  /// The wallet signed, but not as it did when the account was saved here,
  /// so nothing saved opens. Signing in again makes a new profile.
  mismatch,

  /// The wallet is on another account than the one saved here.
  otherAccount,

  /// The wallet derives another ArDrive account than the one saved here
  /// (a profile from before 3.0). Nothing was changed.
  notThisAccount,

  /// Anything else.
  failed,
}

/// Welcome back for an account a browser wallet opens ([wallet]): Continue
/// asks it for one approval. No password.
class PromptWalletUnlock extends LoginState {
  const PromptWalletUnlock({
    required this.wallet,
    this.problem,
  });

  final BrowserWallet wallet;

  /// What went wrong with the last Continue, if anything.
  final WalletUnlockProblem? problem;

  PromptWalletUnlock withProblem(WalletUnlockProblem problem) =>
      PromptWalletUnlock(wallet: wallet, problem: problem);

  @override
  List<Object?> get props => [wallet, problem];
}

/// No record of this MetaMask's ArDrive account was found anywhere: asks
/// whether it was used with ArDrive before. See [AnswerUsedArDriveBefore].
class LoginAskUsedMetaMaskBefore extends LoginState {
  const LoginAskUsedMetaMaskBefore();
}
