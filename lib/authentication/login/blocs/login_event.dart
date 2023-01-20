part of 'login_bloc.dart';

abstract class LoginEvent extends Equatable {
  const LoginEvent();

  @override
  List<Object> get props => [];
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
  const CheckIfUserIsLoggedIn();

  @override
  List<Object> get props => [];
}

class LoginWithPassword extends LoginEvent {
  final String password;
  final Wallet wallet;

  const LoginWithPassword({required this.password, required this.wallet});

  @override
  List<Object> get props => [password];
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

  const CreatePassword({required this.password, required this.wallet});

  @override
  List<Object> get props => [password];
}

class ForgetWallet extends LoginEvent {
  const ForgetWallet();
}

class FinishOnboarding extends LoginEvent {
  const FinishOnboarding({required this.wallet});

  final Wallet wallet;
}
