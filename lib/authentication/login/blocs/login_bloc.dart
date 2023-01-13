import 'dart:convert';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  LoginBloc() : super(LoginInitial()) {
    on<AddWalletFile>((event, emit) async {
      // verify wallet file
      // emit prompt password state
      final wallet =
          Wallet.fromJwk(json.decode(await event.walletFile.readAsString()));

      emit(PromptPassword(walletFile: wallet));
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
