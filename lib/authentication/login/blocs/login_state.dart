part of 'login_bloc.dart';

abstract class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object> get props => [];
}

class LoginInitial extends LoginState {}

class LoginLoading extends LoginState {}

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
