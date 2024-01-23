import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_custom_event_properties.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'stub_web_wallet.dart' // stub implementation
    if (dart.library.html) 'web_wallet.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnectService;

  bool ignoreNextWaletSwitch = false;

  @visibleForTesting
  String? lastKnownWalletAddress;

  @visibleForTesting
  ProfileType? profileType;

  bool usingSeedphrase = false;
  bool existingUserFlow = false;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
    required ArConnectService arConnectService,
    required UserRepository userRepository,
  })  : _arDriveAuth = arDriveAuth,
        _arConnectService = arConnectService,
        super(LoginLoading()) {
    on<LoginEvent>(_onLoginEvent);
    _listenToWalletChange();
  }

  Future<void> _onLoginEvent(LoginEvent event, Emitter<LoginState> emit) async {
    if (event is SelectLoginFlow) {
      await _handleSelectLoginFlowEvent(event, emit);
    } else if (event is AddWalletFile) {
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
    } else if (event is EnterSeedPhrase) {
      await _handleEnterSeedPhrase(event, emit);
    } else if (event is AddWalletFromMnemonic) {
      await _handleAddWalletFromMnemonicEvent(event, emit);
    } else if (event is AddWalletFromCompleter) {
      await _handleAddWalletFromCompleterEvent(event, emit);
    } else if (event is CreateNewWallet) {
      _handleCreateNewWalletEvent(event, emit);
    } else if (event is CompleteWalletGeneration) {
      await _handleCompleteWalletGenerationEvent(event, emit);
    }
  }

  Future<void> _handleSelectLoginFlowEvent(
    SelectLoginFlow event,
    Emitter<LoginState> emit,
  ) async {
    existingUserFlow = event.existingUser;
    emit(LoginInitial(
      isArConnectAvailable: _arConnectService.isExtensionPresent(),
      existingUserFlow: event.existingUser,
    ));
  }

  Future<void> _handleUnlockUserWithBiometricsEvent(
    UnLockWithBiometrics event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    try {
      if (await _arDriveAuth.isUserLoggedIn()) {
        await _loginWithBiometrics(emit: emit);
      }
    } catch (e) {
      logger.e('Failed to unlock user with biometrics.', e);

      usingSeedphrase = false;
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
      logger.e('Invalid wallet file', e);

      return null;
    }
  }

  Future<void> _handleAddWalletFileEvent(
    AddWalletFile event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      profileType = ProfileType.json;

      final wallet =
          Wallet.fromJwk(json.decode(await event.walletFile.readAsString()));

      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(PromptPassword(walletFile: wallet));
      } else {
        emit(LoginOnBoarding(wallet));
      }
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleLoginWithPasswordEvent(
    LoginWithPassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      await _verifyArConnectWalletAddressAndLogIn(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
      );
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleCheckIfUserIsLoggedInEvent(
    CheckIfUserIsLoggedIn event,
    Emitter<LoginState> emit,
  ) async {
    logger.d('Checking if user is logged in');

    emit(LoginLoading());

    if (await _arDriveAuth.isUserLoggedIn()) {
      logger.d('User is logged in');

      if (await _arDriveAuth.isBiometricsEnabled()) {
        logger.d('Biometrics is enabled');

        try {
          await _loginWithBiometrics(emit: emit);
          return;
        } catch (e) {
          logger.e('Failed to unlock user with biometrics', e);
        }
      }
      emit(const PromptPassword());
      return;
    }

    if (event.gettingStarted) {
      _handleCreateNewWalletEvent(const CreateNewWallet(), emit);
    } else {
      emit(const LoginLanding());
      // emit(LoginInitial(
      //   isArConnectAvailable: _arConnectService.isExtensionPresent(),
      // ));
    }
  }

  Future<void> _handleUnlockUserWithPasswordEvent(
    UnlockUserWithPassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    emit(LoginLoading());

    try {
      final user = await _arDriveAuth.unlockUser(password: event.password);

      final type = usingSeedphrase ? LoginType.seedphrase : LoginType.json;
      PlausibleEventTracker.trackLogin(type: type);

      emit(LoginSuccess(user));
    } catch (e) {
      logger.e('Failed to unlock user with password', e);

      usingSeedphrase = false;
      emit(LoginFailure(e));
      emit(previousState);

      return;
    }
  }

  Future<void> _handleCreatePasswordEvent(
    CreatePassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    emit(LoginLoading());

    try {
      await _verifyArConnectWalletAddressAndLogIn(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
      );
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleAddWalletFromArConnectEvent(
    AddWalletFromArConnect event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;
    usingSeedphrase = false;

    try {
      emit(LoginLoading());

      bool hasPermissions = await _arConnectService.checkPermissions();
      if (!hasPermissions) {
        try {
          // If we have partial permissions, we're gonna disconnect before
          /// re-connecting again.
          ignoreNextWaletSwitch = true;
          await _arConnectService.disconnect();
        } catch (_) {}

        await _arConnectService.connect();
      }

      hasPermissions = await _arConnectService.checkPermissions();
      if (!hasPermissions) {
        throw Exception('ArConnect permissions not granted');
      }

      final wallet = ArConnectWallet(_arConnectService);

      profileType = ProfileType.arConnect;

      lastKnownWalletAddress = await wallet.getAddress();

      if (await _arDriveAuth.userHasPassword(wallet)) {
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

    usingSeedphrase = false;

    emit(const LoginLanding());

    // emit(LoginInitial(
    //   isArConnectAvailable: _arConnectService.isExtensionPresent(),
    // ));
  }

  Future<void> _handleFinishOnboardingEvent(
      FinishOnboarding event, Emitter<LoginState> emit) async {
    emit(CreatingNewPassword(walletFile: event.wallet));
  }

  Future<bool> _verifyArConnectWalletAddress() async {
    return lastKnownWalletAddress == await _arConnectService.getWalletAddress();
  }

  Future<void> _verifyArConnectWalletAddressAndLogIn({
    required Wallet wallet,
    required String password,
    required ProfileType profileType,
    required LoginState previousState,
    required Emitter<LoginState> emit,
  }) async {
    if (_isArConnectWallet()) {
      final isArConnectAddressValid = await _verifyArConnectWalletAddress();

      if (!isArConnectAddressValid) {
        usingSeedphrase = false;
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

    final type = profileType == ProfileType.arConnect
        ? LoginType.arConnect
        : usingSeedphrase
            ? LoginType.seedphrase
            : LoginType.json;
    PlausibleEventTracker.trackLogin(type: type);

    emit(LoginSuccess(user));
  }

  bool _isArConnectWallet() {
    return profileType == ProfileType.arConnect;
  }

  void _listenToWalletChange() {
    if (!_arConnectService.isExtensionPresent()) {
      return;
    }

    onArConnectWalletSwitch(() async {
      final isUserLoggedIng = await _arDriveAuth.isUserLoggedIn();
      if (isUserLoggedIng && !_isArConnectWallet()) {
        logger.d(
          'Wallet switch detected for non-arconnect wallet'
          ' ($profileType) - ignoring',
        );
        return;
      }

      if (ignoreNextWaletSwitch) {
        ignoreNextWaletSwitch = false;
        return;
      }

      await _arDriveAuth.logout();

      logger.i('ArConnect wallet switched');
    });
  }

  Future<void> _loginWithBiometrics({
    required Emitter<LoginState> emit,
  }) async {
    emit(LoginLoading());

    final user = await _arDriveAuth.unlockWithBiometrics(
        localizedReason: 'Login using credentials stored on this device');

    const type = LoginType.json;
    PlausibleEventTracker.trackLogin(type: type);
    emit(LoginSuccess(user));

    return;
  }

  Future<void> _handleEnterSeedPhrase(
    EnterSeedPhrase event,
    Emitter<LoginState> emit,
  ) async {
    emit(LoginEnterSeedPhrase());
  }

  Future<void> _handleAddWalletFromMnemonicEvent(
      AddWalletFromMnemonic event, Emitter<LoginState> emit) async {
    profileType = ProfileType.json;
    usingSeedphrase = true;

    emit(const LoginGenerateWallet());

    final wallet = await generateWalletFromMnemonic(event.mnemonic);
    emit(LoginDownloadGeneratedWallet(event.mnemonic, wallet));
  }

  Future<void> _handleAddWalletFromCompleterEvent(
    AddWalletFromCompleter event,
    Emitter<LoginState> emit,
  ) async {
    profileType = ProfileType.json;
    usingSeedphrase = true;

    Completer<Wallet> completer = event.walletCompleter;
    Wallet wallet;

    if (!completer.isCompleted) {
      emit(const LoginGenerateWallet());

      // wait for minimum 3 seconds
      var results = await Future.wait(
          [completer.future, Future.delayed(const Duration(seconds: 3))]);

      wallet = results[0];
    } else {
      wallet = await completer.future;
    }

    emit(LoginDownloadGeneratedWallet(event.mnemonic, wallet));
  }

  void _handleCreateNewWalletEvent(
    CreateNewWallet event,
    Emitter<LoginState> emit,
  ) async {
    profileType = ProfileType.json;
    usingSeedphrase = true;
    final mnemonic = bip39.generateMnemonic();
    emit(LoginCreateNewWallet(mnemonic));
  }

  Future<void> _handleCompleteWalletGenerationEvent(
    CompleteWalletGeneration event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;
    final wallet = event.wallet;

    profileType = ProfileType.json;

    try {
      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(PromptPassword(walletFile: wallet));
      } else {
        emit(LoginOnBoarding(wallet));
      }
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginFailure(e));
      emit(previousState);
    }
  }
}
