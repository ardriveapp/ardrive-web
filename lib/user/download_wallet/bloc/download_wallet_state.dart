part of 'download_wallet_bloc.dart';

abstract class DownloadWalletState extends Equatable {
  const DownloadWalletState();

  @override
  List<Object> get props => [];
}

class DownloadWalletInitial extends DownloadWalletState {}

class DownloadWalletLoading extends DownloadWalletState {}

class DownloadWalletSuccess extends DownloadWalletState {
  const DownloadWalletSuccess();

  @override
  List<Object> get props => [];
}

class DownloadWalletWrongPassword extends DownloadWalletState {
  @override
  List<Object> get props => [];
}

class DownloadWalletFailure extends DownloadWalletState {
  @override
  List<Object> get props => [];
}
