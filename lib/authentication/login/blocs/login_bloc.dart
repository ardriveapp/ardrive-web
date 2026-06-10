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
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/ethereum/ethereum_wallet.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:ardrive/services/solana/solana_identity.dart';
import 'package:ardrive/services/solana/solana_provider.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/graphql_retry.dart';
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

typedef WalletFromMnemonic = Future<Wallet> Function(String mnemonic);

class LoginBloc extends Bloc<LoginEvent, LoginState> {
  final ArDriveAuth _arDriveAuth;
  final ArConnectService _arConnectService;
  final EthereumProviderService _ethereumProviderService;
  final SolanaProviderService _solanaProviderService;
  final TurboUploadService _turboUploadService;
  final ArweaveService _arweaveService;
  final DownloadService _downloadService;
  final ProfileCubit _profileCubit;
  final ConfigService _configService;
  final WalletFromMnemonic _walletFromMnemonic;

  bool ignoreNextWaletSwitch = false;

  @visibleForTesting
  String? lastKnownWalletAddress;

  /// The external wallet address used for login (e.g., Solana public key).
  /// Stored in the profile for display purposes.
  String? _sourceWalletAddress;

  @visibleForTesting
  ProfileType? profileType;

  bool usingSeedphrase = false;
  bool existingUserFlow = true;

  LoginBloc({
    required ArDriveAuth arDriveAuth,
    required ArConnectService arConnectService,
    required EthereumProviderService ethereumProviderService,
    required SolanaProviderService solanaProviderService,
    required TurboUploadService turboUploadService,
    required ArweaveService arweaveService,
    required DownloadService downloadService,
    required UserRepository userRepository,
    required ProfileCubit profileCubit,
    required ConfigService configService,
    WalletFromMnemonic? walletFromMnemonic,
  })  : _arDriveAuth = arDriveAuth,
        _arConnectService = arConnectService,
        _ethereumProviderService = ethereumProviderService,
        _solanaProviderService = solanaProviderService,
        _arweaveService = arweaveService,
        _turboUploadService = turboUploadService,
        _downloadService = downloadService,
        _profileCubit = profileCubit,
        _configService = configService,
        _walletFromMnemonic = walletFromMnemonic ?? generateWalletFromMnemonic,
        super(LoginLoading()) {
    on<LoginEvent>(_onLoginEvent);
    _listenToWalletChange();
  }

  get isArConnectAvailable => _arConnectService.isExtensionPresent();

  get isMetamaskAvailable => _ethereumProviderService.isExtensionPresent();

  get isSolanaAvailable => _solanaProviderService.isExtensionPresent();

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
    } else if (event is LoginWithSolana) {
      await _handleLoginWithSolanaEvent(event, emit);
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
      emit(LoginLoadingIfUserAlreadyExists());

      profileType = ProfileType.json;
      _sourceWalletAddress = null;

      final wallet =
          Wallet.fromJwk(json.decode(await event.walletFile.readAsString()));

      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(LoginLoadingIfUserAlreadyExistsSuccess());
        emit(PromptPassword(wallet: wallet, showWalletCreated: false));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(LoginLoadingIfUserAlreadyExistsSuccess());
        emit(CreateNewPassword(
            wallet: wallet,
            showTutorials: !hasDrives,
            showWalletCreated: false));
      }
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginLoadingIfUserAlreadyExistsSuccess());
      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
      } else {
        emit(LoginFailure(e));
      }
      emit(previousState);
    }
  }

  /// @thiagocarvalhodev it's handling the login and gateway issues
  Future<void> _handleLoginWithPasswordEvent(
    LoginWithPassword event,
    Emitter<LoginState> emit,
  ) async {
    final previousState = state;

    emit(LoginCheckingPassword());

    try {
      if (event.wallet is EthereumWallet) {
        await _handleLoginWithEthereumPassword(event, emit, previousState);
      } else {
        await _handleLoginWithArweavePassword(event, emit, previousState);
      }
    } catch (e) {
      final walletAddress = await event.wallet.getAddress();

      logger.e(
        'Failed to login with password. User\'s address: $walletAddress',
        e,
        StackTrace.current,
      );

      usingSeedphrase = false;

      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(
          e,
          _getGatewayUrl(),
        ));
        return;
      }

      if (e is WrongPasswordException) {
        if (event.wallet is EthereumWallet) {
          emit(PromptPassword(
            wallet: event.wallet,
            derivedEthWallet: event.derivedEthWallet,
            showWalletCreated: false,
            isPasswordInvalid: true,
          ));
        } else {
          emit(LoginPasswordFailed());
        }
        return;
      }

      if (e is PrivateDriveNotFoundException) {
        emit(LoginPasswordFailedWithPrivateDriveNotFound());
        return;
      }

      emit(LoginUnknownFailure(e));
    }
  }

  Future<void> _handleLoginWithEthereumPassword(
    LoginWithPassword event,
    Emitter<LoginState> emit,
    LoginState previousState,
  ) async {
    final derivedEthWallet = event.derivedEthWallet;
    var wallet = event.wallet;
    String? mnemonic;

    if (derivedEthWallet == null) {
      emit(previousState);
      emit(const LoginFailure('Derived ETH wallet is null'));
      return;
    }

    late Uint8List fullEntropy;
    emit(const LoginShowBlockingDialog(
        message:
            'Please approve the request in your Ethereum wallet.'));

    const chainId = 1; // Ethereum mainnet
    try {
      (mnemonic, fullEntropy) = await (wallet as EthereumWallet)
          .deriveArdriveSeedphrase(chainId, event.password);
      emit(LoginCloseBlockingDialog());
    } catch (e) {
      logger.e('Failed to derive Ethereum seedphrase during login', e);
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

    try {
      if (!await _verifyEthereumSignature(
        wallet: wallet,
        derivedEthWallet: derivedEthWallet,
        fullEntropy: fullEntropy,
      )) {
        emit(PromptPassword(
            wallet: event.wallet,
            derivedEthWallet: event.derivedEthWallet,
            showWalletCreated: false,
            isPasswordInvalid: true));
        return;
      }
    } catch (e) {
      if (e is GraphQLException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
        return;
      }

      emit(LoginFailure(e));
      return;
    }

    profileType = ProfileType.json;

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
  }

  Future<bool> _verifyEthereumSignature({
    required Wallet wallet,
    required Wallet derivedEthWallet,
    required Uint8List fullEntropy,
  }) async {
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

      return ethMatches && arMatches;
    }

    return false;
  }

  Future<void> _handleLoginWithArweavePassword(
    LoginWithPassword event,
    Emitter<LoginState> emit,
    LoginState previousState,
  ) async {
    await _verifyArConnectWalletAddressAndLogIn(
      wallet: event.wallet,
      password: event.password,
      emit: emit,
      previousState: previousState,
      profileType: profileType!,
      showTutorials: false,
      showWalletCreated: event.showWalletCreated,
    );
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
    }
  }

  /// @thiagocarvalhodev it's handling the unlock user with password issues
  Future<void> _handleUnlockUserWithPasswordEvent(
    UnlockUserWithPassword event,
    Emitter<LoginState> emit,
  ) async {
    if (_isArConnectWallet()) {
      final arconnectVersionSupported =
          await _arConnectService.isWalletVersionSupported();
      if (!arconnectVersionSupported) {
        emit(const LoginFailure(ArConnectVersionNotSupportedException()));
        return;
      }
    }

    emit(LoginCheckingPassword());

    try {
      final user = await _arDriveAuth.unlockUser(password: event.password);

      emit(LoginSuccess(user));
    } catch (e) {
      logger.e('Failed to unlock user with password', e);

      usingSeedphrase = false;

      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
        return;
      }

      if (e is WrongPasswordException) {
        emit(LoginPasswordFailed());
        return;
      }

      emit(LoginUnknownFailure(e));

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
      if (event.wallet is EthereumWallet) {
        await _handleCreateEthereumPassword(event, emit, previousState);
      } else {
        await _handleCreateArweavePassword(event, emit, previousState);
      }

      emit(LoginCreatePasswordComplete());
    } catch (e, stackTrace) {
      logger.e('[ETH-CREATE] CREATE PASSWORD FAILED', e, stackTrace);
      usingSeedphrase = false;
      // Close any open dialogs (loader, blocking message)
      emit(LoginCloseBlockingDialog());
      emit(LoginFailure(e));
    }
  }

  Future<void> _handleCreateEthereumPassword(
    CreatePassword event,
    Emitter<LoginState> emit,
    LoginState previousState,
  ) async {
    if (event.derivedEthWallet == null) {
      emit(previousState);
      emit(const LoginFailure('Derived ETH wallet is null'));
      return;
    }

    final derivedEthWallet = event.derivedEthWallet!;
    var wallet = event.wallet;
    var mnemonic = event.mnemonic;

    late Uint8List fullEntropy;
    emit(const LoginShowBlockingDialog(
        message:
            'Please approve the request in your Ethereum wallet.'));

    const chainId = 1; // Ethereum mainnet
    logger.d('[ETH-CREATE] Step 1: Requesting MetaMask signature...');
    try {
      (mnemonic, fullEntropy) = await (wallet as EthereumWallet)
          .deriveArdriveSeedphrase(chainId, event.password);
      logger.d('[ETH-CREATE] Step 1 complete: mnemonic derived');
    } catch (e) {
      logger.e('[ETH-CREATE] Step 1 FAILED: derive seedphrase', e);
      emit(LoginCloseBlockingDialog());
      rethrow;
    }
    emit(LoginCloseBlockingDialog());

    logger.d('[ETH-CREATE] Step 2: Generating Arweave wallet from mnemonic...');
    emit(LoginShowLoader());
    wallet = await generateWalletFromMnemonic(mnemonic);
    logger.d('[ETH-CREATE] Step 2 complete: wallet generated');

    logger.d('[ETH-CREATE] Step 3: Signing verification data...');
    final verifySignature = await wallet.sign(fullEntropy);
    logger.d('[ETH-CREATE] Step 3 complete: verification signed');

    // upload verification signature with derived Arweave wallet
    logger.d('[ETH-CREATE] Step 4: Uploading Arweave verification...');
    final dataItem = DataItem.withBlobData(
      data: verifySignature,
      owner: await wallet.getOwner(),
    );
    await dataItem.sign(ArweaveSigner(wallet));

    await _turboUploadService.postDataItem(dataItem: dataItem, wallet: wallet);
    logger.d('[ETH-CREATE] Step 4 complete: Arweave verification uploaded');

    // upload verification signature with derived ETH wallet
    logger.d('[ETH-CREATE] Step 5: Uploading ETH verification...');
    final ethSignedDataItem = DataItem.withBlobData(
      data: verifySignature,
      owner: await derivedEthWallet.getOwner(),
    );

    await ethSignedDataItem.sign(EthereumSigner(derivedEthWallet.credentials));

    await _turboUploadService.postDataItem(
        dataItem: ethSignedDataItem, wallet: derivedEthWallet);
    logger.d('[ETH-CREATE] Step 5 complete: ETH verification uploaded');

    emit(LoginCloseBlockingDialog());

    await _verifyArConnectWalletAddressAndLogIn(
        wallet: wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
        mnemonic: mnemonic,
        showTutorials: event.showTutorials,
        showWalletCreated: event.showWalletCreated);
  }

  Future<void> _handleCreateArweavePassword(
    CreatePassword event,
    Emitter<LoginState> emit,
    LoginState previousState,
  ) async {
    await _verifyArConnectWalletAddressAndLogIn(
        wallet: event.wallet,
        password: event.password,
        emit: emit,
        previousState: previousState,
        profileType: profileType!,
        mnemonic: event.mnemonic,
        showTutorials: event.showTutorials,
        showWalletCreated: event.showWalletCreated);
  }

  Future<void> _handleAddWalletFromArConnectEvent(
    AddWalletFromArConnect event,
    Emitter<LoginState> emit,
  ) async {
    usingSeedphrase = false;
    _sourceWalletAddress = null;

    final arconnectVersionSupported =
        await _arConnectService.isWalletVersionSupported();
    if (!arconnectVersionSupported) {
      emit(const LoginFailure(ArConnectVersionNotSupportedException()));
      return;
    }

    // 1. Connect wallet (ArConnect handles its own popup)
    bool hasPermissions = await _arConnectService.checkPermissions();
    if (!hasPermissions) {
      try {
        // If we have partial permissions, disconnect before reconnecting.
        ignoreNextWaletSwitch = true;
        await _arConnectService.disconnect();
      } catch (_) {}

      try {
        await _arConnectService.connect();
      } catch (e) {
        // User rejected or extension error — return silently
        ignoreNextWaletSwitch = false;
        return;
      }

      // Clear the flag after connect completes — if the wallet switch
      // event was going to fire, it already did during disconnect/connect.
      ignoreNextWaletSwitch = false;
    }

    hasPermissions = await _arConnectService.checkPermissions();
    if (!hasPermissions) {
      // User didn't grant permissions — return silently
      return;
    }

    final wallet = ArConnectWallet(_arConnectService);

    profileType = ProfileType.arConnect;

    lastKnownWalletAddress = await wallet.getAddress();

    // 2. Server-side check (user waits — show blocking dialog)
    emit(const LoginShowBlockingDialog(
        message: 'Setting up your account...'));

    try {
      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(LoginCloseBlockingDialog());
        emit(PromptPassword(wallet: wallet, showWalletCreated: false));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(LoginCloseBlockingDialog());
        emit(
          CreateNewPassword(
            wallet: wallet,
            showTutorials: !hasDrives,
            showWalletCreated: false,
          ),
        );
      }
    } catch (e) {
      emit(LoginCloseBlockingDialog());
      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
      } else {
        emit(LoginFailure(e));
      }
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
    _sourceWalletAddress = null;
    await _solanaProviderService.disconnect();

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
      sourceWalletAddress: _sourceWalletAddress,
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
    _sourceWalletAddress = null;

    emit(LoginShowLoader());

    try {
      final wallet = await generateWalletFromMnemonic(event.mnemonic);

      emit(LoginCloseBlockingDialog());

      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(PromptPassword(wallet: wallet, showWalletCreated: true));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(CreateNewPassword(
            wallet: wallet,
            showTutorials: !hasDrives,
            showWalletCreated: true));
      }
    } catch (e) {
      emit(LoginCloseBlockingDialog());
      emit(LoginFailure(e));
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
    _sourceWalletAddress = null;
    final mnemonic = bip39.generateMnemonic();

    emit(LoginShowLoader());

    try {
      final wallet = await generateWalletFromMnemonic(mnemonic);

      emit(LoginCloseBlockingDialog());

      emit(CreateNewPassword(
        wallet: wallet,
        mnemonic: mnemonic,
        showTutorials: true,
        showWalletCreated: true));
    } catch (e) {
      emit(LoginCloseBlockingDialog());
      emit(LoginFailure(e));
    }
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
    _sourceWalletAddress = null;
    if (!_ethereumProviderService.isExtensionPresent()) {
      emit(const LoginFailure('Metamask not available'));
      return;
    }

    // 1. Connect wallet (MetaMask handles its own popup)
    EthereumWallet? ethWallet;
    try {
      ethWallet = await _ethereumProviderService.connect();
    } catch (e) {
      // User rejected or extension error — return silently
      return;
    }

    if (ethWallet == null) {
      return;
    }

    _sourceWalletAddress = await ethWallet.getAddress();

    // 2. Sign verification message (MetaMask handles its own popup)
    const signMessage = 'Sign message to verify wallet address.';

    late EthereumProviderWallet derivedEthWallet;
    try {
      final signature =
          await ethWallet.sign(Uint8List.fromList(signMessage.codeUnits));

      final signatureSha256 = await sha256.hash(signature);

      final privateKey = web3credentials.EthPrivateKey(
          Uint8List.fromList(signatureSha256.bytes));

      derivedEthWallet = EthereumProviderWallet(privateKey);
    } catch (e) {
      // User rejected signature or extension error — return silently
      return;
    }

    // 3. Server-side check (user waits — show blocking dialog)
    emit(const LoginShowBlockingDialog(
        message: 'Setting up your account...'));

    final arweaveNativeAddressForEth =
        await ownerToAddress(await derivedEthWallet.getOwner());

    String? ethFirstTxId;
    try {
      ethFirstTxId =
          await _arweaveService.getFirstTxForWallet(arweaveNativeAddressForEth);
    } catch (e) {
      emit(LoginCloseBlockingDialog());

      if (e is GraphQLException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
        return;
      }

      emit(LoginFailure(e));
      return;
    }

    emit(LoginCloseBlockingDialog());

    if (ethFirstTxId != null) {
      emit(PromptPassword(
          wallet: ethWallet,
          derivedEthWallet: derivedEthWallet,
          sourceWalletAddress: _sourceWalletAddress,
          showWalletCreated: false));
    } else {
      emit(CreateNewPassword(
          wallet: ethWallet,
          derivedEthWallet: derivedEthWallet,
          sourceWalletAddress: _sourceWalletAddress,
          showTutorials: true,
          showWalletCreated: false));
    }
  }

  Future<void> _handleLoginWithSolanaEvent(
    LoginWithSolana event,
    Emitter<LoginState> emit,
  ) async {
    if (!_solanaProviderService.isExtensionPresent()) {
      emit(const LoginFailure(
          'No Solana wallet detected. Please install Phantom or Solflare.'));
      return;
    }

    try {
      // 1. Connect wallet (Phantom/Solflare handles its own popup)
      final connection =
          await _solanaProviderService.connect(provider: event.provider);

      if (connection == null) {
        await _solanaProviderService.disconnect();
        return;
      }

      _sourceWalletAddress = connection.address;

      // 2. Sign identity message (wallet extension shows its own popup)
      final Uint8List signature;
      try {
        signature = await _solanaProviderService
            .signMessage(solanaIdentityMessage);
      } catch (e) {
        await _solanaProviderService.disconnect();
        _sourceWalletAddress = null;
        return;
      }

      // 3. Derive wallet and check account (show themed loader)
      emit(const LoginShowBlockingDialog(
          message: 'Setting up your account...'));

      final mnemonic = await deriveMnemonicFromSolanaSignature(signature);
      final wallet = await _walletFromMnemonic(mnemonic);

      // 4. From here, it's a standard JWK wallet
      profileType = ProfileType.json;

      // 5. Check if user has existing drives
      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(LoginCloseBlockingDialog());
        emit(PromptPassword(
          wallet: wallet,
          showWalletCreated: false,
          sourceWalletAddress: _sourceWalletAddress,
        ));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(LoginCloseBlockingDialog());
        emit(CreateNewPassword(
          wallet: wallet,
          showTutorials: !hasDrives,
          showWalletCreated: false,
          sourceWalletAddress: _sourceWalletAddress,
        ));
      }
    } catch (e) {
      await _solanaProviderService.disconnect();
      _sourceWalletAddress = null;
      emit(LoginCloseBlockingDialog());
      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
      } else {
        emit(LoginFailure(e));
      }
    }
  }

  String _getGatewayUrl() {
    return _configService.config.arweaveGatewayUrl ?? defaultGraphqlGateway;
  }
}
