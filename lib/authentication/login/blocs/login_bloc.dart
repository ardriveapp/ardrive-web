import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
  })  : _arDriveAuth = arDriveAuth,
        super(LoginInitial()) {
    on<LoginEvent>((event, emit) async {
      if (event is AddWalletFile) {
        emit(LoginLoading());

        final wallet =
            Wallet.fromJwk(json.decode(await event.walletFile.readAsString()));

        if (await _arDriveAuth.isExistingUser(wallet)) {
          emit(PromptPassword(walletFile: wallet));
        } else {
          emit(CreatingNewPassword(walletFile: wallet));
        }
      } else if (event is LoginWithPassword) {
        final previousState = state;

        try {
          emit(LoginLoading());

          final user = await _arDriveAuth.login(event.wallet, event.password);

          emit(LoginSuccess(user));
        } catch (e) {
          emit(LoginFailure(e));
          emit(previousState);
        }
      } else if (event is CheckIfUserIsLoggedIn) {
        emit(LoginLoading());

        if (await _arDriveAuth.isUserLoggedIn()) {
          emit(const PromptPassword());
          return;
        }

        emit(LoginInitial());
      } else if (event is UnlockUserWithPassword) {
        final previousState = state;

        emit(LoginLoading());

        try {
          final user = await _arDriveAuth.unlockUser(password: event.password);
          emit(LoginSuccess(user));
        } catch (e) {
          await Future.delayed(const Duration(seconds: 1));
          emit(LoginFailure(e));
          emit(previousState);

          return;
        }
      } else if (event is CreatePassword) {
        final previousState = state;

        try {
          emit(LoginLoading());

          final user = await _arDriveAuth.addUser(
            event.wallet,
            event.password,
          );

          emit(LoginSuccess(user));
        } catch (e) {
          emit(LoginFailure(e));
          emit(previousState);
        }
      } else if (event is ForgetWallet) {
        emit(LoginInitial());
      }
    });
  }

  Future<Wallet?> validateAndReturnWalletFile(IOFile walletFile) async {
    // verify wallet file
    Wallet wallet;

    try {
      wallet = Wallet.fromJwk(json.decode(await walletFile.readAsString()));

      return wallet;
    } catch (e) {
      return null;
    }
  }
}
