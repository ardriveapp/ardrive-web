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
