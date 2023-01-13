part of 'login_bloc.dart';

abstract class LoginState extends Equatable {
  const LoginState();

  @override
  List<Object> get props => [];
}

class LoginInitial extends LoginState {}

class PromptPassword extends LoginState {
  const PromptPassword({required this.walletFile});

  final Wallet walletFile;
}
