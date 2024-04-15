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

class LoginShowLoader extends LoginState {}

class LoginShowBlockingDialog extends LoginState {
  const LoginShowBlockingDialog({required this.message});

  final String message;
}

class LoginCloseBlockingDialog extends LoginState {}

class LoginTutorials extends LoginState {
  const LoginTutorials(
      {required this.wallet, this.mnemonic, required this.showWalletCreated});

  final Wallet wallet;
  final String? mnemonic;
  final bool showWalletCreated;
}

class PromptPassword extends LoginState {
  const PromptPassword(
      {this.mnemonic,
      this.wallet,
      this.derivedEthWallet,
      this.alreadyLoggedIn = false,
      this.showWalletCreated = false,
      this.isPasswordInvalid = false});

  final String? mnemonic;
  final Wallet? wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final bool alreadyLoggedIn;
  final bool isPasswordInvalid;

  /// Used to determine next screens to show on password success
  final bool showWalletCreated;

  @override
  List<Object?> get props => [mnemonic, wallet, showWalletCreated];
}

class CreateNewPassword extends LoginState {
  const CreateNewPassword(
      {required this.wallet,
      this.derivedEthWallet,
      this.mnemonic,
      required this.showTutorials,
      required this.showWalletCreated});

  final String? mnemonic;
  final Wallet wallet;
  final EthereumProviderWallet? derivedEthWallet;

  /// Used to determine next screens to show on password success
  final bool showTutorials;
  final bool showWalletCreated;

  @override
  List<Object?> get props =>
      [mnemonic, wallet, showTutorials, showWalletCreated];
}

class LoginFailure extends LoginState {
  const LoginFailure(this.error);

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

class LoginCreatePasswordComplete extends LoginState {}
