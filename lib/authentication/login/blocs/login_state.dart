part of 'login_bloc.dart';

abstract class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object> get props => [];
}

class LoginInitial extends LoginState {
  const LoginInitial(this.isArConnectAvailable);

  final bool isArConnectAvailable;
}

class LoginLoading extends LoginState {
  const LoginLoading();
}

class LoginOnBoarding extends LoginState {
  const LoginOnBoarding(this.walletFile);

  final Wallet walletFile;
}

class PromptPassword extends LoginState {
  const PromptPassword({this.walletFile});

  final Wallet? walletFile;
}

class CreatingNewPassword extends LoginState {
  const CreatingNewPassword({required this.walletFile});

  final Wallet walletFile;
}

class LoginFailure extends LoginState {
  const LoginFailure(this.error);

  final Object error;
}

class LoginSuccess extends LoginState {
  const LoginSuccess(this.user);
  final User user;
}

class LoginEnterSeedPhrase extends LoginState {}

class LoginGenerateWallet extends LoginState {
  const LoginGenerateWallet();
}

class LoginDownloadGeneratedWallet extends LoginState {
  const LoginDownloadGeneratedWallet(this.mnemonic, this.walletFile);
  final String mnemonic;
  final Wallet walletFile;
}

class LoginCreateNewWallet extends LoginState {
  const LoginCreateNewWallet(this.mnemonic);
  final String mnemonic;
}

class LoginConfirmMnemonic extends LoginState {
  const LoginConfirmMnemonic(this.mnemonic, this.walletFile);
  final String mnemonic;
  final Wallet walletFile;
}
