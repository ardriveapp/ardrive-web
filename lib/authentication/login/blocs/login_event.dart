part of 'login_bloc.dart';

abstract class LoginEvent extends Equatable {
  const LoginEvent();

  @override
  List<Object> get props => [];
}

class SelectLoginFlow extends LoginEvent {
  const SelectLoginFlow({required this.existingUser});

  final bool existingUser;

  @override
  List<Object> get props => [existingUser];
}

/// A keyfile was chosen and read. It carries the wallet, not the file: the
/// file is read once, by [LoginBloc.validateAndReturnWalletFile], because a
/// second read can fail where the first didn't.
class AddWalletFile extends LoginEvent {
  const AddWalletFile(this.wallet);

  final Wallet wallet;

  @override
  List<Object> get props => [wallet];
}

class AddWalletFromArConnect extends LoginEvent {
  const AddWalletFromArConnect();

  @override
  List<Object> get props => [];
}

class CheckIfUserIsLoggedIn extends LoginEvent {
  final bool gettingStarted;

  const CheckIfUserIsLoggedIn({
    this.gettingStarted = false,
  });

  @override
  List<Object> get props => [gettingStarted];
}

class LoginWithPassword extends LoginEvent {
  final String password;
  final Wallet wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final bool showWalletCreated;

  const LoginWithPassword({
    required this.password,
    required this.wallet,
    this.derivedEthWallet,
    required this.showWalletCreated,
  });

  @override
  List<Object> get props => [password, wallet, showWalletCreated];
}

class UnlockUserWithPassword extends LoginEvent {
  final String password;

  const UnlockUserWithPassword({
    required this.password,
  });

  @override
  List<Object> get props => [password];
}

class CreatePassword extends LoginEvent {
  final String password;
  final Wallet wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final String? mnemonic;
  final bool isNewUser;
  final bool showWalletCreated;

  const CreatePassword(
      {required this.password,
      required this.wallet,
      this.derivedEthWallet,
      this.mnemonic,
      required this.isNewUser,
      required this.showWalletCreated});

  @override
  List<Object> get props => [password, wallet, isNewUser, showWalletCreated];
}

/// Forgets the account stored on this device: Welcome back's "Use a
/// different account", after its confirmation. Signs it out and deletes its
/// profile and this device's data.
class ForgetWallet extends LoginEvent {
  const ForgetWallet();
}

/// Leaves the wallet a sign-in or a sign-up has loaded, from its password
/// dialog's close or "Use a different wallet", back to Log in ([toLogIn]) or
/// the first panel.
///
/// Forgets an account stored on this device only if this flow saved it: a
/// sign-up whose password step failed after its profile was saved. An
/// account that was here before (a returning user who reached Sign up or Log
/// in again) is never touched, whichever wallet it is.
class LeaveWallet extends LoginEvent {
  const LeaveWallet({this.toLogIn = false});

  final bool toLogIn;

  @override
  List<Object> get props => [toLogIn];
}

/// Asks again for the password of a new account whose password step failed,
/// for the same wallet: making another would take a minute.
class RetrySignUpPassword extends LoginEvent {
  const RetrySignUpPassword();
}

/// "Try again" after [LoginPasswordOpensNoDrives].
class RetrySignInPassword extends LoginEvent {
  const RetrySignInPassword();
}

/// "Continue" after [LoginPasswordOpensNoDrives]: sign in with the drives the
/// password didn't open locked.
class ContinueSignInWithLockedDrives extends LoginEvent {
  const ContinueSignInWithLockedDrives();
}

class FinishOnboarding extends LoginEvent {
  const FinishOnboarding({required this.wallet});

  final Wallet wallet;

  @override
  List<Object> get props => [wallet];
}

class UnLockWithBiometrics extends LoginEvent {
  const UnLockWithBiometrics();
}

/// Opens the recovery phrase panel, which also takes a keyfile.
class EnterSeedPhrase extends LoginEvent {
  const EnterSeedPhrase();
}

/// Back to the first panel, Log in and Sign up.
class ShowLanding extends LoginEvent {
  const ShowLanding();
}

/// Stops waiting on a browser wallet and goes back to Log in. Whatever the
/// wallet answers afterwards is ignored.
class CancelWalletLogin extends LoginEvent {
  const CancelWalletLogin();
}

class AddWalletFromSeedPhraseLogin extends LoginEvent {
  const AddWalletFromSeedPhraseLogin(this.mnemonic);

  final String mnemonic;

  @override
  List<Object> get props => [mnemonic];
}

class AddWalletFromCompleter extends LoginEvent {
  const AddWalletFromCompleter(this.mnemonic, this.walletCompleter);

  final String mnemonic;
  final Completer<Wallet> walletCompleter;

  @override
  List<Object> get props => [mnemonic, walletCompleter];
}

class GenerateWallet extends LoginEvent {
  const GenerateWallet();
}

class CreateNewWallet extends LoginEvent {
  const CreateNewWallet();
}

/// Sign up on the first panel: offers the browser wallets found, if any,
/// before a new account; with none, makes the account straight away.
class StartSignUp extends LoginEvent {
  const StartSignUp({this.fromLogIn = false});

  /// Opened from Log in's "Create an account": Back returns there.
  final bool fromLogIn;

  @override
  List<Object> get props => [fromLogIn];
}

class CompleteWalletGeneration extends LoginEvent {
  const CompleteWalletGeneration({required this.wallet, this.mnemonic});

  final Wallet wallet;
  final String? mnemonic;

  @override
  List<Object> get props => [wallet];
}

class LoginWithMetamask extends LoginEvent {
  const LoginWithMetamask();
}

class LoginWithSolana extends LoginEvent {
  const LoginWithSolana({this.provider});

  /// Optional provider preference: 'phantom', 'solflare', or null for auto.
  final String? provider;

  @override
  List<Object> get props => [provider ?? ''];
}

/// Continue on Welcome back for an account a browser wallet opens: one
/// approval in that wallet.
class UnlockWithWallet extends LoginEvent {
  const UnlockWithWallet();
}

/// The answer to "Have you used ArDrive with this MetaMask before?", asked
/// when no record of the account was found anywhere.
class AnswerUsedArDriveBefore extends LoginEvent {
  const AnswerUsedArDriveBefore({required this.usedBefore});

  final bool usedBefore;

  @override
  List<Object> get props => [usedBefore];
}
