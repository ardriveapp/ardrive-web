import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnectService;

  @visibleForTesting
  String? lastKnownWalletAddress;

  @visibleForTesting
  ProfileType? profileType;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
    required ArConnectService arConnectService,
  })  : _arDriveAuth = arDriveAuth,
        _arConnectService = arConnectService,
        super(LoginLoading()) {
    on<LoginEvent>(_onLoginEvent);
    _listenToWalletChange();
  }

  Future<void> _onLoginEvent(LoginEvent event, Emitter<LoginState> emit) async {
    if (event is AddWalletFile) {
      await _handleAddWalletFileEvent(event, emit);
    } else if (event is LoginWithPassword) {
      await _handleLoginWithPasswordEvent(event, emit);
    } else if (event is CheckIfUserIsLoggedIn) {
      await _handleCheckIfUserIsLoggedInEvent(event, emit);
    } else if (event is UnlockUserWithPassword) {
      await _handleUnlockUserWithPasswordEvent(event, emit);
    } else if (event is CreatePassword) {
      await _handleCreatePasswordEvent(event, emit);
    } else if (event is AddWalletFromArConnect) {
      await _handleAddWalletFromArConnectEvent(event, emit);
    } else if (event is ForgetWallet) {
      await _handleForgetWalletEvent(event, emit);
    } else if (event is FinishOnboarding) {
      await _handleFinishOnboardingEvent(event, emit);
    } else if (event is UnLockWithBiometrics) {
      await _handleUnlockUserWithBiometricsEvent(event, emit);
    }
  }

  Future<void> _handleUnlockUserWithBiometricsEvent(
      UnLockWithBiometrics event, Emitter<LoginState> emit) async {
    final previousState = state;

    try {
      if (await _arDriveAuth.isUserLoggedIn()) {
        await _loginWithBiometrics(emit: emit);
      }
    } catch (e) {
      logger.e('Failed to unlock user with biometrics: $e');

      emit(LoginFailure(e));

      emit(previousState);
    }
  }

  Future<Wallet?> validateAndReturnWalletFile(IOFile walletFile) async {
    try {
      final wallet =
          Wallet.fromJwk(json.decode(await walletFile.readAsString()));

      return wallet;
    } catch (e) {
      logger.d('Invalid wallet file: $e');

      return null;
    }
  }

  Future<void> _handleAddWalletFileEvent(
      AddWalletFile event, Emitter<LoginState> emit) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      profileType = ProfileType.json;

      final wallet =
          Wallet.fromJwk(json.decode(await event.walletFile.readAsString()));

      if (await _arDriveAuth.isExistingUser(wallet)) {
        emit(PromptPassword(walletFile: wallet));
      } else {
        emit(LoginOnBoarding(wallet));
      }
    } catch (e) {
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleLoginWithPasswordEvent(
      LoginWithPassword event, Emitter<LoginState> emit) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      await _verifyArConnectWalletAddressAndLogin(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
      );
    } catch (e) {
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleCheckIfUserIsLoggedInEvent(
      CheckIfUserIsLoggedIn event, Emitter<LoginState> emit) async {
    emit(LoginLoading());

    if (await _arDriveAuth.isUserLoggedIn()) {
      if (await _arDriveAuth.isBiometricsEnabled()) {
        try {
          await _loginWithBiometrics(emit: emit);
          return;
        } catch (e) {
          logger.e('Failed to unlock user with biometrics: $e');
        }
      }

      emit(const PromptPassword());

      return;
    }

    emit(LoginInitial(_arConnectService.isExtensionPresent()));
  }

  Future<void> _handleUnlockUserWithPasswordEvent(
      UnlockUserWithPassword event, Emitter<LoginState> emit) async {
    final previousState = state;

    emit(LoginLoading());

    try {
      final user = await _arDriveAuth.unlockUser(password: event.password);

      emit(LoginSuccess(user));
    } catch (e) {
      logger.e('Failed to unlock user with password: $e');

      emit(LoginFailure(e));
      emit(previousState);

      return;
    }
  }

  Future<void> _handleCreatePasswordEvent(
      CreatePassword event, Emitter<LoginState> emit) async {
    final previousState = state;

    emit(LoginLoading());

    try {
      await _verifyArConnectWalletAddressAndLogin(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
      );
    } catch (e) {
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleAddWalletFromArConnectEvent(
      AddWalletFromArConnect event, Emitter<LoginState> emit) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      await _arConnectService.connect();

      if (!(await _arConnectService.checkPermissions())) {
        throw Exception('ArConnect permissions not granted');
      }

      final wallet = ArConnectWallet(_arConnectService);

      profileType = ProfileType.arConnect;

      lastKnownWalletAddress = await wallet.getAddress();

      if (await _arDriveAuth.isExistingUser(wallet)) {
        emit(PromptPassword(walletFile: wallet));
      } else {
        emit(LoginOnBoarding(wallet));
      }
    } catch (e) {
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleForgetWalletEvent(
    ForgetWallet event,
    Emitter<LoginState> emit,
  ) async {
    if (await _arDriveAuth.isUserLoggedIn()) {
      await _arDriveAuth.logout();
    }

    if (_isArConnectWallet()) {
      await _arConnectService.disconnect();
    }

    emit(LoginInitial(_arConnectService.isExtensionPresent()));
  }

  Future<void> _handleFinishOnboardingEvent(
      FinishOnboarding event, Emitter<LoginState> emit) async {
    emit(CreatingNewPassword(walletFile: event.wallet));
  }

  Future<bool> _verifyArConnectWalletAddress() async {
    return lastKnownWalletAddress == await _arConnectService.getWalletAddress();
  }

  Future<void> _verifyArConnectWalletAddressAndLogin({
    required Wallet wallet,
    required String password,
    required ProfileType profileType,
    required LoginState previousState,
    required Emitter<LoginState> emit,
  }) async {
    if (_isArConnectWallet()) {
      final isArConnectAddressValid = await _verifyArConnectWalletAddress();

      if (!isArConnectAddressValid) {
        emit(const LoginFailure(WalletMismatchException()));
        emit(previousState);

        return;
      }
    }

    final user = await _arDriveAuth.login(
      wallet,
      password,
      profileType,
    );

    emit(LoginSuccess(user));
  }

  bool _isArConnectWallet() {
    return profileType == ProfileType.arConnect;
  }

  void _listenToWalletChange() {
    if (!_arConnectService.isExtensionPresent()) {
      return;
    }

    onArConnectWalletSwitch(() {
      logger.i('ArConnect wallet switched');
      // ignore: invalid_use_of_visible_for_testing_member
      emit(const LoginFailure(WalletMismatchException()));

      _arDriveAuth.logout();

      // ignore: invalid_use_of_visible_for_testing_member
      emit(const LoginInitial(true));
    });
  }

  Future<void> _loginWithBiometrics({
    required Emitter<LoginState> emit,
  }) async {
    emit(LoginLoading());

    final user = await _arDriveAuth.unlockWithBiometrics(
        localizedReason: 'Login using credentials stored on this device');

    emit(LoginSuccess(user));

    return;
  }
}
