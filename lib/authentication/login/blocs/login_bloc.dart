import 'dart:async';
import 'dart:convert';

import 'package:ardrive/blocs/drive_create/first_drive.dart';
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
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:clock/clock.dart';
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
  final FirstDrive _firstDrive;

  /// The wallet Sign up made in this session, which gets its first drive
  /// once its owner reaches the app.
  String? _signUpWalletAddress;

  bool ignoreNextWaletSwitch = false;

  @visibleForTesting
  String? lastKnownWalletAddress;

  /// The external wallet address used for login (e.g., Solana public key).
  /// Stored in the profile for display purposes.
  String? _sourceWalletAddress;

  @visibleForTesting
  ProfileType? profileType;

  bool usingSeedphrase = false;

  /// A new account's password step that failed, kept to be asked again.
  CreateNewPassword? _signUpToRetry;

  /// Whether a new account's password step failed and can be asked again.
  bool get hasSignUpToRetry => _signUpToRetry != null;
  bool existingUserFlow = true;

  /// Completed by Cancel while a browser wallet is asked for something. Each
  /// request has its own, so a late answer to a cancelled one is dropped.
  Completer<void>? _walletCancel;

  /// Each Solana log in's number, by the wallet it asked for ('*' for any).
  /// A connection approved after Cancel is dropped only if no newer attempt
  /// could be using that wallet.
  int _solanaAttempts = 0;
  final _latestSolanaAttempt = <String, int>{};

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
    FirstDrive? firstDrive,
    Duration walletInjectionWait = const Duration(seconds: 1),
    Duration keyfileReadTimeout = defaultKeyfileReadTimeout,
    Duration walletLookupTimeout = defaultWalletLookupTimeout,
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
        _firstDrive = firstDrive ?? FirstDrive(),
        _walletInjectionWait = walletInjectionWait,
        _keyfileReadTimeout = keyfileReadTimeout,
        _walletLookupTimeout = walletLookupTimeout,
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
    } else if (event is RetrySignUpPassword) {
      final retry = _signUpToRetry;
      _signUpToRetry = null;
      emit(retry == null
          ? const LoginLanding()
          : CreateNewPassword(
              wallet: retry.wallet,
              mnemonic: retry.mnemonic,
              isNewUser: retry.isNewUser,
              showWalletCreated: retry.showWalletCreated,
              fromSignUp: retry.fromSignUp,
              retrying: true,
            ));
    } else if (event is UnLockWithBiometrics) {
      await _handleUnlockUserWithBiometricsEvent(event, emit);
    } else if (event is AddWalletFromSeedPhraseLogin) {
      await _handleAddWalletFromSeedPhraseLoginEvent(event, emit);
    } else if (event is AddWalletFromCompleter) {
      await _handleAddWalletFromCompleterEvent(event, emit);
    } else if (event is CreateNewWallet) {
      await _handleCreateNewWalletEvent(event, emit);
    } else if (event is StartSignUp) {
      await _handleStartSignUpEvent(emit, fromLogIn: event.fromLogIn);
    } else if (event is CompleteWalletGeneration) {
      await _handleCompleteWalletGenerationEvent(event, emit);
    } else if (event is LoginWithMetamask) {
      await _handleLoginWithMetamaskEvent(event, emit);
    } else if (event is LoginWithSolana) {
      await _handleLoginWithSolanaEvent(event, emit);
    } else if (event is EnterSeedPhrase) {
      emit(const LoginEnterRecoveryPhrase());
    } else if (event is ShowLanding) {
      emit(const LoginLanding());
    } else if (event is CancelWalletLogin) {
      await _handleCancelWalletLoginEvent(emit);
    } else if (event is RetrySignInPassword) {
      _handleRetrySignInPassword(emit);
    } else if (event is ContinueSignInWithLockedDrives) {
      await _handleContinueSignInWithLockedDrives(emit);
    }
  }

  /// A sign-in whose password opened none of the wallet's private drives,
  /// waiting for the user to try again or continue. See
  /// [LoginPasswordOpensNoDrives].
  _PendingSignIn? _pendingSignIn;

  /// Back to the password, with what was typed selected.
  void _handleRetrySignInPassword(Emitter<LoginState> emit) {
    final pending = _pendingSignIn;
    _pendingSignIn = null;

    if (pending == null) {
      return;
    }

    // MetaMask's password dialog closes when it is submitted, so it is asked
    // again; any other wallet's is still open beneath.
    if (pending.promptWallet is EthereumWallet) {
      emit(PromptPassword(
        wallet: pending.promptWallet,
        derivedEthWallet: pending.derivedEthWallet,
        sourceWalletAddress: _sourceWalletAddress,
        showWalletCreated: pending.showWalletCreated,
      ));
      return;
    }

    emit(const LoginPasswordRetry());
  }

  /// Signs in anyway: the drives the password didn't open stay locked.
  Future<void> _handleContinueSignInWithLockedDrives(
    Emitter<LoginState> emit,
  ) async {
    final pending = _pendingSignIn;
    _pendingSignIn = null;

    if (pending == null) {
      return;
    }

    emit(LoginCheckingPassword());

    try {
      await _verifyArConnectWalletAddressAndLogIn(
        wallet: pending.wallet,
        password: pending.password,
        profileType: pending.profileType,
        previousState: pending.previousState,
        emit: emit,
        mnemonic: pending.mnemonic,
        isNewUser: pending.isNewUser,
        showWalletCreated: pending.showWalletCreated,
        skipDriveCheck: true,
      );
    } catch (e) {
      logger.e('Failed to sign in with the drives locked', e);
      usingSeedphrase = false;
      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
        return;
      }
      emit(LoginUnknownFailure(e));
    }
  }

  /// The panel a browser wallet was chosen on: Log in, or Sign up's choice.
  LoginState get _logInPanel => LoginInitial(
        isArConnectAvailable: _arConnectService.isExtensionPresent(),
        existingUserFlow: existingUserFlow,
      );

  /// Whether any browser wallet that can log in is in this browser.
  bool get anyWalletDetected =>
      _arConnectService.isExtensionPresent() ||
      _ethereumProviderService.isExtensionPresent() ||
      _solanaProviderService.isExtensionPresent();

  /// Whether Sign up's choice was opened from Log in, so its Back goes
  /// there rather than to the first panel.
  bool signUpFromLogIn = false;

  /// How long the get-started link looks for a wallet extension before
  /// deciding there is none. On a fresh page load an extension can inject
  /// itself after the app starts.
  final Duration _walletInjectionWait;

  /// Whether a wallet extension is in this browser, looking again for up to
  /// [_walletInjectionWait] when there is none yet.
  Future<bool> _walletDetectedSoon() async {
    final until = clock.now().add(_walletInjectionWait);
    while (!anyWalletDetected) {
      if (!clock.now().isBefore(until)) return false;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return true;
  }

  Future<void> _handleStartSignUpEvent(
    Emitter<LoginState> emit, {
    bool fromLogIn = false,
    bool waitForWallets = false,
  }) async {
    signUpFromLogIn = fromLogIn;
    final walletFound =
        waitForWallets ? await _walletDetectedSoon() : anyWalletDetected;
    if (walletFound) {
      existingUserFlow = false;
      // Every way in (the Sign up button, Log in's link, the get-started
      // link) reports the panel here, once.
      PlausibleEventTracker.trackPageview(page: PlausiblePageView.signUpPage);
      emit(_logInPanel);
    } else {
      await _handleCreateNewWalletEvent(
          const CreateNewWallet(noWalletFound: true), emit);
    }
  }

  /// Shows the panel that waits on [wallet] and returns what Cancel
  /// completes.
  Completer<void> _askWallet(Emitter<LoginState> emit, BrowserWallet wallet) {
    final previous = _walletCancel;
    if (previous != null && !previous.isCompleted) previous.complete();
    final cancel = Completer<void>();
    _walletCancel = cancel;
    emit(LoginWaitingOnWallet(wallet: wallet));
    return cancel;
  }

  /// The wallet answered, so there is nothing left to cancel.
  void _walletAnswered(Completer<void> cancel) {
    if (identical(_walletCancel, cancel)) _walletCancel = null;
  }

  /// [request]'s answer, or [WalletLoginCancelled] once Cancel is pressed,
  /// whichever comes first. An extension that never answers can't keep the
  /// panel waiting.
  Future<T> _walletAnswer<T>(Completer<void> cancel, Future<T> request) async {
    if (cancel.isCompleted) throw const WalletLoginCancelled();
    final answer = await Future.any<Object?>([
      request,
      cancel.future.then((_) => null),
    ]);
    if (cancel.isCompleted) throw const WalletLoginCancelled();
    return answer as T;
  }

  Future<void> _handleCancelWalletLoginEvent(Emitter<LoginState> emit) async {
    final cancel = _walletCancel;
    final waitingOn = state;
    if (cancel == null || waitingOn is! LoginWaitingOnWallet) return;

    _walletCancel = null;
    cancel.complete();
    ignoreNextWaletSwitch = false;
    _sourceWalletAddress = null;
    emit(_logInPanel);

    final wallet = waitingOn.wallet;
    if (wallet != BrowserWallet.wander && wallet != BrowserWallet.metamask) {
      // Phantom and Solflare can drop a connection; the others can't.
      await _disconnectSolana(_solanaProviderName(wallet));
    }
  }

  /// The Solana bridge's name for [wallet], or null for another wallet.
  static String? _solanaProviderName(BrowserWallet wallet) => switch (wallet) {
        BrowserWallet.phantom => 'phantom',
        BrowserWallet.solflare => 'solflare',
        _ => null,
      };

  /// Drops the connection to [provider], the wallet that was asked, not
  /// whichever one the bridge would pick.
  Future<void> _disconnectSolana(String? provider) async {
    try {
      await _solanaProviderService.disconnect(provider: provider);
    } catch (e) {
      logger.w('Could not disconnect the Solana wallet after Cancel');
    }
  }

  /// The wallet's extension failed rather than answering: back to Log in,
  /// with an error.
  void _walletFailed(
      Completer<void> cancel, Emitter<LoginState> emit, Object error) {
    logger.w('The browser wallet failed while asked to log in');
    _walletAnswered(cancel);
    ignoreNextWaletSwitch = false;
    _sourceWalletAddress = null;
    emit(_logInPanel);
    emit(LoginFailure(error));
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

  /// How long reading a chosen keyfile may take. A keyfile is a few KB and
  /// reads at once; a read still going after this is stuck.
  static const defaultKeyfileReadTimeout = Duration(seconds: 15);

  /// How long the lookups for a chosen wallet (its password, its drives) may
  /// go without receiving anything before the dialog closes with an error.
  ///
  /// Counted from the last page received, not from the start: the lookup
  /// pages through every drive transaction the wallet has, and a real wallet
  /// took 30 pages and 18.5 s on a fast link. A wallet that big on a slow
  /// phone still logs in; a gateway that stops answering still fails here.
  ///
  /// Longer than a stalled page's first two GraphQL attempts (20 s, then
  /// 40 s, see [GraphQLRetry.attemptTimeoutFor]) and the pause between them,
  /// so a page that times out once is retried before the dialog gives up.
  static const defaultWalletLookupTimeout = Duration(seconds: 65);

  final Duration _keyfileReadTimeout;
  final Duration _walletLookupTimeout;

  /// The wallet in a chosen keyfile, or null if the file isn't a keyfile.
  ///
  /// Throws [KeyfileUnreadableException] if the file can't be read, or the
  /// read doesn't finish within the keyfile read timeout.
  Future<Wallet?> validateAndReturnWalletFile(IOFile walletFile) async {
    final Uint8List bytes;
    try {
      bytes = await walletFile.readAsBytes().timeout(_keyfileReadTimeout);
    } catch (e) {
      // Only the type: what failed is all that's needed here.
      logger.w('Could not read the chosen keyfile: ${e.runtimeType}');
      throw const KeyfileUnreadableException();
    }
    try {
      final wallet = Wallet.fromJwk(json.decode(utf8.decode(bytes)));

      return wallet;
    } catch (e) {
      // Not the error itself: a parse error quotes the file, which can be
      // a key.
      logger.w('The chosen file is not a keyfile');

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

      final wallet = event.wallet;

      // Both lookups ask the gateway. A stalled one closes the dialog with
      // an error instead of spinning for ever. The address first: the
      // lookups start as soon as their future is made.
      final address = await wallet.getAddress();
      final (hasPassword, hasDrives) = await _untilIdle(
        () async {
          if (await _arDriveAuth.userHasPassword(wallet)) {
            return (true, true);
          }
          return (false, await _arDriveAuth.isExistingUser(wallet));
        }(),
        address: address,
      );

      emit(LoginLoadingIfUserAlreadyExistsSuccess());
      if (hasPassword) {
        emit(PromptPassword(wallet: wallet, showWalletCreated: false));
      } else {
        emit(CreateNewPassword(
            wallet: wallet, isNewUser: !hasDrives, showWalletCreated: false));
      }
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginLoadingIfUserAlreadyExistsSuccess());
      if (e is TimeoutException) {
        logger.w('Looking up the chosen wallet timed out');
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
      } else if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
      } else {
        emit(LoginFailure(e));
      }
      emit(previousState);
    }
  }

  /// [work], or a [TimeoutException] once the wallet lookup timeout passes
  /// with no page of [address]'s drives received. Each page restarts it.
  Future<T> _untilIdle<T>(Future<T> work, {required String address}) {
    final done = Completer<T>();
    Timer? deadline;
    void restart() {
      deadline?.cancel();
      deadline = Timer(_walletLookupTimeout, () {
        if (!done.isCompleted) {
          done.completeError(TimeoutException(
              'Nothing received for the wallet', _walletLookupTimeout));
        }
      });
    }

    final pages = _arweaveService.userDriveTxPageReceived
        .where((page) => page == address)
        .listen((_) => restart());
    restart();
    work.then((value) {
      if (!done.isCompleted) done.complete(value);
    }, onError: (Object e, StackTrace s) {
      if (!done.isCompleted) done.completeError(e, s);
    });
    return done.future.whenComplete(() {
      deadline?.cancel();
      pages.cancel();
    });
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
        message: 'Please approve the request in your Ethereum wallet.'));

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
      isNewUser: false,
      showWalletCreated: false,
      promptWallet: event.wallet,
      derivedEthWallet: derivedEthWallet,
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
      isNewUser: false,
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

    // The welcome panel shows while this check runs, and the check can be
    // slow while the database opens. If Log in or Sign up was pressed in
    // the meantime, that panel stays: the welcome panel isn't put back
    // over it.
    if (state is! LoginLoading) {
      logger.d('A panel was chosen while checking for an account');
      return;
    }

    if (event.gettingStarted) {
      // The same choice as Sign up, after a moment for a wallet extension
      // that is still injecting itself. Awaited: it emits for up to a
      // minute.
      await _handleStartSignUpEvent(emit, waitForWallets: true);
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
      // A new account's wallet took a minute to make. Kept, so once the
      // error is read the same password step opens again for it.
      if (previousState is CreateNewPassword &&
          previousState.mnemonic != null) {
        _signUpToRetry = previousState;
      }
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
        message: 'Please approve the request in your Ethereum wallet.'));

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
        isNewUser: event.isNewUser,
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
        isNewUser: event.isNewUser,
        showWalletCreated: event.showWalletCreated);
  }

  Future<void> _handleAddWalletFromArConnectEvent(
    AddWalletFromArConnect event,
    Emitter<LoginState> emit,
  ) async {
    usingSeedphrase = false;
    _sourceWalletAddress = null;

    final cancel = _askWallet(emit, BrowserWallet.wander);
    final ArConnectWallet wallet;
    try {
      final arconnectVersionSupported = await _walletAnswer(
          cancel, _arConnectService.isWalletVersionSupported());
      if (!arconnectVersionSupported) {
        _walletAnswered(cancel);
        emit(_logInPanel);
        emit(const LoginFailure(ArConnectVersionNotSupportedException()));
        return;
      }

      // 1. Connect wallet (ArConnect handles its own popup)
      bool hasPermissions =
          await _walletAnswer(cancel, _arConnectService.checkPermissions());
      if (!hasPermissions) {
        try {
          // If we have partial permissions, disconnect before reconnecting.
          ignoreNextWaletSwitch = true;
          await _walletAnswer(cancel, _arConnectService.disconnect());
        } on WalletLoginCancelled {
          rethrow;
        } catch (_) {}

        try {
          await _walletAnswer(cancel, _arConnectService.connect());
        } on WalletLoginCancelled {
          rethrow;
        } catch (e) {
          // User rejected or extension error: back to Log in, no error.
          ignoreNextWaletSwitch = false;
          _walletAnswered(cancel);
          emit(_logInPanel);
          return;
        }

        // Clear the flag after connect completes — if the wallet switch
        // event was going to fire, it already did during disconnect/connect.
        ignoreNextWaletSwitch = false;
      }

      hasPermissions =
          await _walletAnswer(cancel, _arConnectService.checkPermissions());
      if (!hasPermissions) {
        // User didn't grant permissions: back to Log in, no error.
        _walletAnswered(cancel);
        emit(_logInPanel);
        return;
      }

      wallet = ArConnectWallet(_arConnectService);
      lastKnownWalletAddress = await _walletAnswer(cancel, wallet.getAddress());
    } on WalletLoginCancelled {
      return;
    } catch (e) {
      _walletFailed(cancel, emit, e);
      return;
    }
    _walletAnswered(cancel);

    profileType = ProfileType.arConnect;

    // 2. Server-side check (user waits — show blocking dialog)
    emit(_logInPanel);
    emit(const LoginShowBlockingDialog(
        message: 'Setting up your account.\nThis may take a moment.'));

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
            isNewUser: !hasDrives,
            showWalletCreated: false,
            fromSignUp: !existingUserFlow,
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
    _signUpToRetry = null;
    await _solanaProviderService.disconnect();

    emit(const LoginLanding());
  }

  Future<void> _handleFinishOnboardingEvent(
      FinishOnboarding event, Emitter<LoginState> emit) async {
    if (await _arDriveAuth.isUserLoggedIn()) {
      final address = await event.wallet.getAddress();
      if (address == _signUpWalletAddress) {
        try {
          await _firstDrive.request(address);
        } catch (e, stackTrace) {
          // Without it the new user lands on Getting started instead.
          logger.e('Could not ask for the first drive', e, stackTrace);
        }
      }

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
      required bool isNewUser,
      required bool showWalletCreated,
      Wallet? promptWallet,
      EthereumProviderWallet? derivedEthWallet,
      bool skipDriveCheck = false}) async {
    if (_isArConnectWallet()) {
      final isArConnectAddressValid = await _verifyArConnectWalletAddress();

      if (!isArConnectAddressValid) {
        usingSeedphrase = false;
        emit(const LoginFailure(WalletMismatchException()));
        emit(previousState);

        return;
      }
    }

    final User user;
    try {
      user = skipDriveCheck
          ? await _arDriveAuth.login(
              wallet,
              password,
              profileType,
              sourceWalletAddress: _sourceWalletAddress,
              skipDriveCheck: true,
            )
          : await _arDriveAuth.login(
              wallet,
              password,
              profileType,
              sourceWalletAddress: _sourceWalletAddress,
            );
    } on PasswordOpensNoDriveException {
      // Not a wrong password: the user may correct it or continue with
      // those drives locked. Sign-in is never blocked by its drives.
      _pendingSignIn = _PendingSignIn(
        wallet: wallet,
        password: password,
        profileType: profileType,
        previousState: previousState,
        mnemonic: mnemonic,
        isNewUser: isNewUser,
        showWalletCreated: showWalletCreated,
        promptWallet: promptWallet ?? wallet,
        derivedEthWallet: derivedEthWallet,
      );
      emit(const LoginPasswordOpensNoDrives());
      return;
    }

    if (showWalletCreated) {
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
      final wallet = await _walletFromMnemonic(event.mnemonic);

      emit(LoginCloseBlockingDialog());

      if (await _arDriveAuth.userHasPassword(wallet)) {
        emit(PromptPassword(wallet: wallet, showWalletCreated: true));
      } else {
        final hasDrives = await _arDriveAuth.isExistingUser(wallet);
        emit(CreateNewPassword(
            wallet: wallet, isNewUser: !hasDrives, showWalletCreated: true));
      }
    } catch (e) {
      usingSeedphrase = false;
      emit(LoginCloseBlockingDialog());
      if (e is AuthenticationGatewayException) {
        emit(GatewayLoginFailure(e, _getGatewayUrl()));
      } else {
        emit(LoginFailure(e));
      }
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

    emit(LoginCreatingAccount(noWalletFound: event.noWalletFound));

    try {
      final wallet = await _walletFromMnemonic(mnemonic);
      _signUpWalletAddress = await wallet.getAddress();

      emit(CreateNewPassword(
          wallet: wallet,
          mnemonic: mnemonic,
          isNewUser: true,
          showWalletCreated: true));
    } catch (e) {
      emit(LoginFailure(e));
      emit(const LoginLanding());
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

    final cancel = _askWallet(emit, BrowserWallet.metamask);
    final EthereumWallet ethWallet;
    late EthereumProviderWallet derivedEthWallet;
    try {
      // 1. Connect wallet (MetaMask handles its own popup)
      EthereumWallet? connected;
      try {
        connected =
            await _walletAnswer(cancel, _ethereumProviderService.connect());
      } on WalletLoginCancelled {
        rethrow;
      } catch (e) {
        // User rejected or extension error: back to Log in, no error.
        connected = null;
      }

      if (connected == null) {
        _walletAnswered(cancel);
        emit(_logInPanel);
        return;
      }
      ethWallet = connected;

      try {
        _sourceWalletAddress =
            await _walletAnswer(cancel, ethWallet.getAddress());
      } on WalletLoginCancelled {
        rethrow;
      } catch (e) {
        _walletFailed(cancel, emit, e);
        return;
      }

      // 2. Sign verification message (MetaMask handles its own popup)
      emit(const LoginWaitingOnWallet(
        wallet: BrowserWallet.metamask,
        request: BrowserWalletRequest.signIn,
      ));
      const signMessage = 'Sign message to verify wallet address.';

      try {
        final signature = await _walletAnswer(
            cancel, ethWallet.sign(Uint8List.fromList(signMessage.codeUnits)));

        final signatureSha256 = await sha256.hash(signature);

        final privateKey = web3credentials.EthPrivateKey(
            Uint8List.fromList(signatureSha256.bytes));

        derivedEthWallet = EthereumProviderWallet(privateKey);
      } on WalletLoginCancelled {
        rethrow;
      } catch (e) {
        // User rejected signature or extension error: back to Log in.
        _sourceWalletAddress = null;
        _walletAnswered(cancel);
        emit(_logInPanel);
        return;
      }
    } on WalletLoginCancelled {
      return;
    }
    _walletAnswered(cancel);

    // 3. Server-side check (user waits — show blocking dialog)
    emit(_logInPanel);
    emit(const LoginShowBlockingDialog(
        message: 'Setting up your account.\nThis may take a moment.'));

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
          isNewUser: true,
          showWalletCreated: false,
          fromSignUp: !existingUserFlow));
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

    final browserWallet = switch (event.provider) {
      'phantom' => BrowserWallet.phantom,
      'solflare' => BrowserWallet.solflare,
      _ => BrowserWallet.otherSolana,
    };
    final cancel = _askWallet(emit, browserWallet);
    final attempt = ++_solanaAttempts;
    _latestSolanaAttempt[event.provider ?? '*'] = attempt;
    var settingUp = false;

    try {
      final Uint8List signature;
      final connecting =
          _solanaProviderService.connect(provider: event.provider);
      var connected = false;
      try {
        // 1. Connect wallet (Phantom/Solflare handles its own popup)
        final connection = await _walletAnswer(cancel, connecting);
        connected = true;

        if (connection == null) {
          _walletAnswered(cancel);
          emit(_logInPanel);
          await _solanaProviderService.disconnect();
          return;
        }

        _sourceWalletAddress = connection.address;

        // 2. Sign identity message (wallet extension shows its own popup)
        emit(LoginWaitingOnWallet(
          wallet: browserWallet,
          request: BrowserWalletRequest.signIn,
        ));
        try {
          signature = await _walletAnswer(cancel,
              _solanaProviderService.signMessage(solanaIdentityMessage));
        } on WalletLoginCancelled {
          rethrow;
        } catch (e) {
          _walletAnswered(cancel);
          emit(_logInPanel);
          await _solanaProviderService.disconnect();
          _sourceWalletAddress = null;
          return;
        }
      } on WalletLoginCancelled {
        // Cancel has gone back to Log in and dropped the connection. If the
        // wallet approves the connection afterwards, drop that too.
        if (connected) return;
        unawaited(connecting.then((connection) async {
          if (connection == null) return;
          final provider = connection.providerType;
          final newer = (_latestSolanaAttempt[provider] ?? 0) > attempt ||
              (_latestSolanaAttempt['*'] ?? 0) > attempt;
          if (!newer) await _disconnectSolana(provider);
        }, onError: (_) {}));
        return;
      }
      _walletAnswered(cancel);
      emit(_logInPanel);

      // 3. Derive wallet and check account (show themed loader)
      emit(const LoginShowBlockingDialog(
          message: 'Setting up your account.\nThis may take a moment.'));
      settingUp = true;

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
          isNewUser: !hasDrives,
          showWalletCreated: false,
          sourceWalletAddress: _sourceWalletAddress,
          fromSignUp: !existingUserFlow,
        ));
      }
    } catch (e) {
      _walletAnswered(cancel);
      await _solanaProviderService.disconnect();
      _sourceWalletAddress = null;
      // Closes the dialog only if it opened: before it, there is none, and
      // the pop would close the page instead.
      if (settingUp) {
        emit(LoginCloseBlockingDialog());
      } else {
        emit(_logInPanel);
      }
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

/// Cancel was pressed while a browser wallet was asked for something.
class WalletLoginCancelled implements Exception {
  const WalletLoginCancelled();
}

/// A chosen keyfile couldn't be read: the read failed, or never finished.
/// Not the same as a file that was read and isn't a keyfile.
class KeyfileUnreadableException implements Exception {
  const KeyfileUnreadableException();
}

/// What a sign-in held back by [LoginPasswordOpensNoDrives] needs to go on.
class _PendingSignIn {
  const _PendingSignIn({
    required this.wallet,
    required this.password,
    required this.profileType,
    required this.previousState,
    required this.mnemonic,
    required this.isNewUser,
    required this.showWalletCreated,
    required this.promptWallet,
    required this.derivedEthWallet,
  });

  /// The Arweave wallet signing in.
  final Wallet wallet;
  final String password;
  final ProfileType profileType;
  final LoginState previousState;
  final String? mnemonic;
  final bool isNewUser;
  final bool showWalletCreated;

  /// The wallet the password was asked for: for MetaMask, the Ethereum one.
  final Wallet promptWallet;
  final EthereumProviderWallet? derivedEthWallet;
}
