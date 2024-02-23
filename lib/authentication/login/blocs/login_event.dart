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

class AddWalletFile extends LoginEvent {
  const AddWalletFile(this.walletFile);

  final IOFile walletFile;

  @override
  List<Object> get props => [walletFile];
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
  final bool showWalletCreated;

  const LoginWithPassword({
    required this.password,
    required this.wallet,
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
  final bool showTutorials;
  final bool showWalletCreated;

  const CreatePassword(
      {required this.password,
      required this.wallet,
      required this.showTutorials,
      required this.showWalletCreated});

  @override
  List<Object> get props =>
      [password, wallet, showTutorials, showWalletCreated];
}

class ForgetWallet extends LoginEvent {
  const ForgetWallet();
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

class EnterSeedPhrase extends LoginEvent {
  const EnterSeedPhrase();
}

class AddWalletFromSeedPhraseLogin extends LoginEvent {
  const AddWalletFromSeedPhraseLogin(this.mnemonic, this.wallet);

  final String mnemonic;
  final Wallet wallet;

  @override
  List<Object> get props => [mnemonic, wallet];
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

class CompleteWalletGeneration extends LoginEvent {
  const CompleteWalletGeneration(this.wallet);

  final Wallet wallet;

  @override
  List<Object> get props => [wallet];
}
