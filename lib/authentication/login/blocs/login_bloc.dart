import 'dart:async';
import 'dart:convert';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/ethereum_signer.dart';
import 'package:ardrive/authentication/login/blocs/stub_web_wallet.dart' // stub implementation
    if (dart.library.html) 'package:ardrive/authentication/login/blocs/web_wallet.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:webthree/credentials.dart' as web3credentials;

part 'login_event.dart';
part 'login_state.dart';

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnectService;
  final EthereumProviderService _ethereumProviderService;
  final TurboUploadService _turboUploadService;
  final ArweaveService _arweaveService;
  final DownloadService _downloadService;
  final ProfileCubit _profileCubit;

  bool ignoreNextWaletSwitch = false;

  @visibleForTesting
  String? lastKnownWalletAddress;

  @visibleForTesting
  ProfileType? profileType;

  bool usingSeedphrase = false;
  bool existingUserFlow = true;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
    required ArConnectService arConnectService,
    required EthereumProviderService ethereumProviderService,
    required TurboUploadService turboUploadService,
    required ArweaveService arweaveService,
    required DownloadService downloadService,
    required UserRepository userRepository,
    required ProfileCubit profileCubit,
  })  : _arDriveAuth = arDriveAuth,
        _arConnectService = arConnectService,
        _ethereumProviderService = ethereumProviderService,
        _arweaveService = arweaveService,
        _turboUploadService = turboUploadService,
        _downloadService = downloadService,
        _profileCubit = profileCubit,
        super(LoginLoading()) {
    on<LoginEvent>(_onLoginEvent);
    _listenToWalletChange();
  }

  get isArConnectAvailable => _arConnectService.isExtensionPresent();

  get isMetamaskAvailable => _ethereumProviderService.isExtensionPresent();

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
    } else if (event is AddWalletFromSeedPhraseLogin) {
      await _handleAddWalletFromSeedPhraseLoginEvent(event, emit);
    } else if (event is AddWalletFromCompleter) {
      await _handleAddWalletFromCompleterEvent(event, emit);
    } else if (event is CreateNewWallet) {
      await _handleCreateNewWalletEvent(event, emit);
    } else if (event is CompleteWalletGeneration) {
      await _handleCompleteWalletGenerationEvent(event, emit);
    } else if (event is LoginWithMetamask) {
      await _handleLoginWithMetamaskEvent(event, emit);
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
        emit(PromptPassword(wallet: wallet, showWalletCreated: false));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(CreateNewPassword(
            wallet: wallet,
            showTutorials: !hasDrives,
            showWalletCreated: false));
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

    var wallet = event.wallet;
    String? mnemonic;

    if (wallet is EthereumWallet) {
      final derivedEthWallet = event.derivedEthWallet;

      if (derivedEthWallet == null) {
        emit(previousState);
        emit(const LoginFailure('Derived ETH wallet is null'));
        return;
      }

      late Uint8List fullEntropy;
      emit(const LoginShowBlockingDialog(
          message:
              'Sign the following data with Metamask to secure your wallet and sign in.'));

      const chainId = 1; // Ethereum mainnet
      try {
        (mnemonic, fullEntropy) =
            await wallet.deriveArdriveSeedphrase(chainId, event.password);
        emit(LoginCloseBlockingDialog());
      } catch (e) {
        emit(LoginCloseBlockingDialog());
        emit(PromptPassword(
            wallet: event.wallet,
            derivedEthWallet: event.derivedEthWallet,
            showWalletCreated: false,
            isPasswordInvalid: true));
        return;
      }
      emit(LoginShowLoader());
      wallet = await generateWalletFromMnemonic(mnemonic);
      emit(LoginCloseBlockingDialog());

      final verifySignature = await wallet.sign(fullEntropy);

      // Check GQL for generated wallet to see if the password matches
      int? firstTxBlockHeight = await _arweaveService
          .getFirstTxBlockHeightForWallet(await wallet.getAddress());

      var firstBlockTxs = firstTxBlockHeight != null
          ? await _arweaveService.getTransactionsAtHeight(
              await wallet.getAddress(), firstTxBlockHeight)
          : null;

      var firstBlockTxsFilteredBySize =
          firstBlockTxs?.where((tx) => tx.$2 == verifySignature.length);

      final arweaveNativeAddressForEth =
          await ownerToAddress(await derivedEthWallet.getOwner());

      final String? ethFirstTxId =
          await _arweaveService.getFirstTxForWallet(arweaveNativeAddressForEth);

      if (firstBlockTxsFilteredBySize != null && ethFirstTxId != null) {
        final ethRecordedSignature =
            await _downloadService.download(ethFirstTxId, false);

        final ethMatches = listEquals(
          ethRecordedSignature,
          verifySignature,
        );

        bool arMatches = false;

        if (ethMatches) {
          for (var tx in firstBlockTxsFilteredBySize) {
            final recordedSignature =
                await _downloadService.download(tx.$1, false);

            if (listEquals(recordedSignature, verifySignature)) {
              arMatches = true;
              break;
            }
          }
        }

        if (!ethMatches || !arMatches) {
          emit(PromptPassword(
              wallet: event.wallet,
              derivedEthWallet: event.derivedEthWallet,
              showWalletCreated: false,
              isPasswordInvalid: true));
          return;
        }

        profileType = ProfileType.json;

        try {
          emit(LoginLoading());

          await _verifyArConnectWalletAddressAndLogIn(
            wallet: wallet,
            password: event.password,
            emit: emit,
            previousState: previousState,
            profileType: profileType!,
            mnemonic: mnemonic,
            showTutorials: false,
            showWalletCreated: false,
          );
        } catch (e) {
          emit(PromptPassword(
              wallet: event.wallet,
              derivedEthWallet: event.derivedEthWallet,
              showWalletCreated: false,
              isPasswordInvalid: true));
        }
      } else {
        emit(PromptPassword(
            wallet: event.wallet,
            derivedEthWallet: event.derivedEthWallet,
            showWalletCreated: false,
            isPasswordInvalid: true));
      }
    } else {
      try {
        emit(LoginCheckingPassword());

        await _verifyArConnectWalletAddressAndLogIn(
          wallet: wallet,
          password: event.password,
          emit: emit,
          previousState: previousState,
          profileType: profileType!,
          showTutorials: false,
          showWalletCreated: event.showWalletCreated,
        );
      } catch (e) {
        usingSeedphrase = false;
        emit(LoginPasswordFailed());
      }
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
      emit(const PromptPassword(alreadyLoggedIn: true));
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
    emit(LoginCheckingPassword());

    try {
      final user = await _arDriveAuth.unlockUser(password: event.password);

      emit(LoginSuccess(user));
    } catch (e) {
      logger.e('Failed to unlock user with password', e);

      usingSeedphrase = false;
      emit(LoginPasswordFailed());

      return;
    }
  }

  Future<void> _handleCreatePasswordEvent(
    CreatePassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    emit(LoginLoading());

    var wallet = event.wallet;
    var mnemonic = event.mnemonic;

    if (wallet is EthereumWallet) {
      if (event.derivedEthWallet == null) {
        emit(previousState);
        emit(const LoginFailure('Derived ETH wallet is null'));
        return;
      }
      final derivedEthWallet = event.derivedEthWallet!;

      late Uint8List fullEntropy;
      emit(const LoginShowBlockingDialog(
          message:
              'Sign the following data with Metamask to secure your wallet and sign in.'));

      const chainId = 1; // Ethereum mainnet
      try {
        (mnemonic, fullEntropy) =
            await wallet.deriveArdriveSeedphrase(chainId, event.password);
      } catch (e) {
        // emit(LoginFailure(e));
        emit(previousState);
        return;
      } finally {
        emit(LoginCloseBlockingDialog());
      }

      emit(LoginShowLoader());
      wallet = await generateWalletFromMnemonic(mnemonic);

      final verifySignature = await wallet.sign(fullEntropy);

      // upload verification signature with derived Arweave wallet
      final dataItem = DataItem.withBlobData(
        data: verifySignature,
        owner: await wallet.getOwner(),
      );
      await dataItem.sign(ArweaveSigner(wallet));

      await _turboUploadService.postDataItem(
          dataItem: dataItem, wallet: wallet);

      // upload verification signature with derived ETH wallet
      final ethSignedDataItem = DataItem.withBlobData(
        data: verifySignature,
        owner: await derivedEthWallet.getOwner(),
      );

      await ethSignedDataItem
          .sign(EthereumSigner(derivedEthWallet.credentials));

      await _turboUploadService.postDataItem(
          dataItem: ethSignedDataItem, wallet: derivedEthWallet);

      emit(LoginCloseBlockingDialog());
    }

    try {
      await _verifyArConnectWalletAddressAndLogIn(
          wallet: wallet,
          password: event.password,
          emit: emit,
          previousState: previousState,
          profileType: profileType!,
          mnemonic: mnemonic,
          showTutorials: event.showTutorials,
          showWalletCreated: event.showWalletCreated);

      emit(LoginCreatePasswordComplete());
    } catch (e) {
      usingSeedphrase = false;
      emit(previousState);
      emit(LoginFailure(e));
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
        emit(PromptPassword(wallet: wallet, showWalletCreated: false));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(
          CreateNewPassword(
            wallet: wallet,
            showTutorials: !hasDrives,
            showWalletCreated: false,
          ),
        );
      }
    } catch (e) {
      emit(previousState);
      emit(LoginFailure(e));
    }
  }

  Future<void> _handleForgetWalletEvent(
    ForgetWallet event,
    Emitter<LoginState> emit,
  ) async {
    if (await _arDriveAuth.isUserLoggedIn()) {
      await _arDriveAuth
          .logout()
          .then((value) => _profileCubit.logoutProfile());
    }

    usingSeedphrase = false;

    emit(const LoginLanding());
  }

  Future<void> _handleFinishOnboardingEvent(
      FinishOnboarding event, Emitter<LoginState> emit) async {
    if (await _arDriveAuth.isUserLoggedIn()) {
      emit(LoginSuccess(_arDriveAuth.currentUser));
    } else {
      // should not happen as user should be logged in by this point
      emit(const LoginFailure('Error logging in user'));
    }
  }

  Future<bool> _verifyArConnectWalletAddress() async {
    return lastKnownWalletAddress == await _arConnectService.getWalletAddress();
  }

  Future<void> _verifyArConnectWalletAddressAndLogIn(
      {required Wallet wallet,
      required String password,
      required ProfileType profileType,
      required LoginState previousState,
      required Emitter<LoginState> emit,
      String? mnemonic,
      required bool showTutorials,
      required bool showWalletCreated}) async {
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

    if (showTutorials) {
      emit(LoginTutorials(
          wallet: wallet,
          mnemonic: mnemonic,
          showWalletCreated: showWalletCreated));
    } else if (showWalletCreated) {
      emit(LoginDownloadGeneratedWallet(wallet: wallet, mnemonic: mnemonic));
    } else {
      emit(LoginSuccess(user));
    }
  }

  bool _isArConnectWallet() {
    return profileType == ProfileType.arConnect;
  }

  void _listenToWalletChange() {
    if (!_arConnectService.isExtensionPresent()) {
      return;
    }

    onArConnectWalletSwitch(() async {
      logger.d('Wallet switch detected on LoginBloc');
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

    emit(LoginSuccess(user));

    return;
  }

  Future<void> _handleAddWalletFromSeedPhraseLoginEvent(
      AddWalletFromSeedPhraseLogin event, Emitter<LoginState> emit) async {
    profileType = ProfileType.json;
    usingSeedphrase = true;

    emit(LoginShowLoader());

    final wallet = await generateWalletFromMnemonic(event.mnemonic);

    emit(LoginCloseBlockingDialog());

    if (await _arDriveAuth.userHasPassword(wallet)) {
      emit(PromptPassword(wallet: wallet, showWalletCreated: true));
    } else {
      final hasDrives = await _arDriveAuth.isExistingUser(wallet);
      emit(CreateNewPassword(
          wallet: wallet, showTutorials: !hasDrives, showWalletCreated: true));
    }
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
      // emit(const LoginGenerateWallet());

      // wait for minimum 3 seconds
      var results = await Future.wait(
          [completer.future, Future.delayed(const Duration(seconds: 3))]);

      wallet = results[0];
    } else {
      wallet = await completer.future;
    }

    emit(
        LoginDownloadGeneratedWallet(mnemonic: event.mnemonic, wallet: wallet));
  }

  Future<void> _handleCreateNewWalletEvent(
    CreateNewWallet event,
    Emitter<LoginState> emit,
  ) async {
    profileType = ProfileType.json;
    usingSeedphrase = true;
    final mnemonic = bip39.generateMnemonic();

    emit(LoginShowLoader());

    final wallet = await generateWalletFromMnemonic(mnemonic);

    emit(LoginCloseBlockingDialog());

    emit(CreateNewPassword(
        wallet: wallet,
        mnemonic: mnemonic,
        showTutorials: true,
        showWalletCreated: true));
  }

  Future<void> _handleCompleteWalletGenerationEvent(
    CompleteWalletGeneration event,
    Emitter<LoginState> emit,
  ) async {
    final wallet = event.wallet;
    profileType = ProfileType.json;

    emit(
        LoginDownloadGeneratedWallet(wallet: wallet, mnemonic: event.mnemonic));
  }

  Future<void> _handleLoginWithMetamaskEvent(
      LoginWithMetamask event, Emitter<LoginState> emit) async {
    profileType = ProfileType.json;
    if (!_ethereumProviderService.isExtensionPresent()) {
      emit(const LoginFailure('Metamask not available'));
      return;
    }
    emit(const LoginShowBlockingDialog(
        message: 'Please connect your Metamask wallet'));

    EthereumWallet? ethWallet;
    try {
      ethWallet = await _ethereumProviderService.connect();
    } catch (e) {
      emit(LoginCloseBlockingDialog());
      emit(LoginFailure(e));
      return;
    }

    emit(LoginCloseBlockingDialog());

    if (ethWallet == null) {
      emit(const LoginFailure('Unable to connect to Metamask'));
      return;
    }

    // Sign message to verify user address and use signature to derive in-memory
    // ETH wallet

    const signMessage = 'Sign message to verify wallet address.';

    emit(const LoginShowBlockingDialog(
        message:
            'Sign the following data with Metamask to verify your wallet address.'));

    late EthereumProviderWallet derivedEthWallet;
    try {
      final signature =
          await ethWallet.sign(Uint8List.fromList(signMessage.codeUnits));

      final signatureSha256 = await sha256.hash(signature);

      final privateKey = web3credentials.EthPrivateKey(
          Uint8List.fromList(signatureSha256.bytes));

      derivedEthWallet = EthereumProviderWallet(privateKey);
    } catch (e) {
      emit(LoginCloseBlockingDialog());
      emit(LoginFailure(e));
      return;
    }

    final arweaveNativeAddressForEth =
        await ownerToAddress(await derivedEthWallet.getOwner());

    final String? ethFirstTxId =
        await _arweaveService.getFirstTxForWallet(arweaveNativeAddressForEth);

    emit(LoginCloseBlockingDialog());

    if (ethFirstTxId != null) {
      emit(PromptPassword(
          wallet: ethWallet,
          derivedEthWallet: derivedEthWallet,
          showWalletCreated: false));
    } else {
      emit(CreateNewPassword(
          wallet: ethWallet,
          derivedEthWallet: derivedEthWallet,
          showTutorials: true,
          showWalletCreated: true));
    }
  }
}
