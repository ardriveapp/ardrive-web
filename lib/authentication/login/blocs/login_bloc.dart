import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/entities/profile_source.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'stub_web_wallet.dart' // stub implementation
    if (dart.library.html) 'web_wallet.dart';

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnectService;
  final EthereumProviderService _ethereumProviderService;

  bool ignoreNextWaletSwitch = false;

  @visibleForTesting
  String? lastKnownWalletAddress;

  @visibleForTesting
  ProfileType? profileType;

  @visibleForTesting
  ProfileSource? profileSource;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
    required ArConnectService arConnectService,
    required EthereumProviderService ethereumProviderService,
  })  : _arDriveAuth = arDriveAuth,
        _arConnectService = arConnectService,
        _ethereumProviderService = ethereumProviderService,
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
    } else if (event is AddWalletFromEthereumProviderEvent) {
      await _handleAddWalletFromEthereumProviderEvent(event, emit);
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
      await _handleCreateNewWalletEvent(event, emit);
    } else if (event is CompleteWalletGeneration) {
      await _handleCompleteWalletGenerationEvent(event, emit);
    }
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
      profileSource = const ProfileSource(type: ProfileSourceType.standalone);

      final wallet =
          Wallet.fromJwk(json.decode(await event.walletFile.readAsString()));

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

  Future<void> _handleLoginWithPasswordEvent(
    LoginWithPassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      await _verifyArConnectWalletAddressAndLogin(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
        profileSource: profileSource!,
      );
    } catch (e) {
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleCheckIfUserIsLoggedInEvent(
    CheckIfUserIsLoggedIn event,
    Emitter<LoginState> emit,
  ) async {
    emit(LoginLoading());

    if (await _arDriveAuth.isUserLoggedIn()) {
      if (await _arDriveAuth.isBiometricsEnabled()) {
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

    emit(LoginInitial(_arConnectService.isExtensionPresent(),
        _ethereumProviderService.isExtensionPresent()));
  }

  Future<void> _handleUnlockUserWithPasswordEvent(
    UnlockUserWithPassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    emit(LoginLoading());

    try {
      final user = await _arDriveAuth.unlockUser(password: event.password);

      emit(LoginSuccess(user));
    } catch (e) {
      logger.e('Failed to unlock user with password', e);

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
      await _verifyArConnectWalletAddressAndLogin(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
        profileSource: profileSource!,
      );
    } catch (e) {
      emit(LoginFailure(e));
      emit(previousState);
    }
  }

  Future<void> _handleAddWalletFromArConnectEvent(
    AddWalletFromArConnect event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

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
      profileSource = const ProfileSource(type: ProfileSourceType.standalone);

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

  Future<void> _handleAddWalletFromEthereumProviderEvent(
      AddWalletFromEthereumProviderEvent event,
      Emitter<LoginState> emit) async {
    final previousState = state;

    try {
      emit(LoginLoading());

      final ethereumWallet = await _ethereumProviderService.connect();

      if (ethereumWallet == null) {
        throw Exception('Ethereum wallet not connected');
      }

      final address = await ethereumWallet.getAddress();
      final mnemonic = await ethereumWallet.deriveArdriveSeedphrase();

      profileType = ProfileType.json;
      profileSource = ProfileSource(
        type: ProfileSourceType.ethereumSignature,
        address: address,
      );

      emit(const LoginGenerateWallet());

      final wallet = await generateWalletFromMnemonic(mnemonic);

      emit(LoginDownloadGeneratedWallet(mnemonic, wallet));
    } catch (e) {
      logger.e('Failed to add wallet from Ethereum provider', e);

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

    emit(LoginInitial(_arConnectService.isExtensionPresent(),
        _ethereumProviderService.isExtensionPresent()));
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
    required ProfileSource profileSource,
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
      profileSource,
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

    onArConnectWalletSwitch(() async {
      final isUserLoggedIng = await _arDriveAuth.isUserLoggedIn();
      if (isUserLoggedIng && !_isArConnectWallet()) {
        logger.d('Wallet switch detected. Is current profile ArConnect: false');
        return;
      }

      if (ignoreNextWaletSwitch) {
        ignoreNextWaletSwitch = false;
        return;
      }

      logger.i('ArConnect wallet switched');
      // ignore: invalid_use_of_visible_for_testing_member
      emit(const LoginFailure(WalletMismatchException()));

      await _arDriveAuth.logout();

      // ignore: invalid_use_of_visible_for_testing_member
      emit(LoginInitial(true, _ethereumProviderService.isExtensionPresent()));
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

  Future<void> _handleEnterSeedPhrase(
    EnterSeedPhrase event,
    Emitter<LoginState> emit,
  ) async {
    emit(LoginEnterSeedPhrase());
  }

  Future<void> _handleAddWalletFromMnemonicEvent(
      AddWalletFromMnemonic event, Emitter<LoginState> emit) async {
    profileType = ProfileType.json;
    profileSource = const ProfileSource(type: ProfileSourceType.standalone);

    emit(const LoginGenerateWallet());

    final wallet = await generateWalletFromMnemonic(event.mnemonic);
    emit(LoginDownloadGeneratedWallet(event.mnemonic, wallet));
  }

  Future<void> _handleAddWalletFromCompleterEvent(
    AddWalletFromCompleter event,
    Emitter<LoginState> emit,
  ) async {
    profileType = ProfileType.json;
    profileSource = const ProfileSource(type: ProfileSourceType.standalone);

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

  Future<void> _handleCreateNewWalletEvent(
    CreateNewWallet event,
    Emitter<LoginState> emit,
  ) async {
    profileType = ProfileType.json;
    profileSource = const ProfileSource(type: ProfileSourceType.standalone);

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
    // Wallet could be from Ethereum or Arweave wallet file
    // profileSource = ProfileSource(type: ProfileSourceType.arweaveKey);

    try {
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
}
