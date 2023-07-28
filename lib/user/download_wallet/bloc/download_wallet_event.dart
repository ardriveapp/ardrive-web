part of 'download_wallet_bloc.dart';

abstract class DownloadWalletEvent extends Equatable {
  const DownloadWalletEvent();

  @override
  List<Object> get props => [];
}

class DownloadWallet extends DownloadWalletEvent {
  final String password;

  const DownloadWallet(this.password);

  @override
  List<Object> get props => [password];
}
