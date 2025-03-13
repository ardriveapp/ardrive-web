import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'download_wallet_event.dart';
part 'download_wallet_state.dart';

class DownloadWalletBloc
    extends Bloc<DownloadWalletEvent, DownloadWalletState> {
  final ArDriveAuth _ardriveAuth;
  final ArDriveIOUtils _ardriveIOUtils;

  DownloadWalletBloc({
    required ArDriveAuth ardriveAuth,
    required ArDriveIOUtils ardriveIOUtils,
  })  : _ardriveIOUtils = ardriveIOUtils,
        _ardriveAuth = ardriveAuth,
        super(DownloadWalletInitial()) {
    on<DownloadWalletEvent>(
      (event, emit) async {
        if (event is DownloadWallet) {
          emit(DownloadWalletLoading());
          try {
            await _ardriveAuth.unlockUser(password: event.password);
          } catch (e) {
            emit(DownloadWalletWrongPassword());
            return;
          }
          try {
            final wallet = _ardriveAuth.currentUser.wallet;

            await _ardriveIOUtils.downloadWalletAsJsonFile(
              wallet: wallet,
              onDownloadComplete: (success) {
                if (!success) {
                  emit(DownloadWalletFailure());
                } else {
                  emit(const DownloadWalletSuccess());
                }
              },
            );
          } catch (e) {
            emit(DownloadWalletFailure());
          }
        }
      },
    );
  }
}
