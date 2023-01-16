import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnectService;

  String? _lastKnownWalletAddress;
  ProfileType? _profileType;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
    required ArConnectService arConnectService,
  })  : _arDriveAuth = arDriveAuth,
        _arConnectService = arConnectService,
        super(LoginInitial(
          arConnectService.isExtensionPresent(),
        )) {
    on<LoginEvent>((event, emit) async {
      if (event is AddWalletFile) {
        emit(LoginLoading());

        _profileType = ProfileType.json;

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

          if (_profileType == ProfileType.arConnect &&
              _lastKnownWalletAddress !=
                  await _arConnectService.getWalletAddress()) {
            emit(const LoginFailure(WalletMismatchException()));
            emit(previousState);

            return;
          }

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

        emit(LoginInitial(_arConnectService.isExtensionPresent()));
      } else if (event is UnlockUserWithPassword) {
        final previousState = state;

        emit(LoginLoading());

        try {
          final user = await _arDriveAuth.unlockUser(password: event.password);

          emit(LoginSuccess(user));
        } catch (e) {
          emit(LoginFailure(e));
          emit(previousState);

          return;
        }
      } else if (event is CreatePassword) {
        final previousState = state;

        try {
          emit(LoginLoading());

          if (_profileType == ProfileType.arConnect &&
              _lastKnownWalletAddress !=
                  await _arConnectService.getWalletAddress()) {
            emit(const LoginFailure(WalletMismatchException()));
            emit(previousState);

            return;
          }

          final user = await _arDriveAuth.addUser(
            event.wallet,
            event.password,
            _profileType!,
          );

          emit(LoginSuccess(user));
        } catch (e) {
          emit(LoginFailure(e));
          emit(previousState);
        }
      } else if (event is AddWalletFromArConnect) {
        emit(LoginLoading());

        await _arConnectService.connect();

        if (!(await _arConnectService.checkPermissions())) {
          emit(const LoginFailure('ArConnect permissions not granted'));
          return;
        }

        final wallet = ArConnectWallet();

        _profileType = ProfileType.arConnect;

        _lastKnownWalletAddress = await wallet.getAddress();

        // split this logic into a separate function
        if (await _arDriveAuth.isExistingUser(wallet)) {
          emit(PromptPassword(walletFile: wallet));
        } else {
          emit(CreatingNewPassword(walletFile: wallet));
        }
      } else if (event is ForgetWallet) {
        if (await _arDriveAuth.isUserLoggedIn()) {
          await _arDriveAuth.logout();
        }

        emit(LoginInitial(_arConnectService.isExtensionPresent()));
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
