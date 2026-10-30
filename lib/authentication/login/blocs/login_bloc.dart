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
import 'package:ardrive_logger/ardrive_logger.dart' show UntrackedException;
import 'package:ardrive/device_unlock/domain/device_key.dart';
import 'package:ardrive/device_unlock/domain/device_secret_source.dart';
import 'package:ardrive/device_unlock/domain/device_unlocker.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/models/daos/profile_dao.dart'
    show ProfileFormatTooNewException;
import 'package:ardrive/services/ethereum/ethereum_account.dart';
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
  final ArweaveService _arweaveService;
  final TurboUploadService _turboUploadService;
  final DownloadService _downloadService;
  final ProfileCubit _profileCubit;
  final ConfigService _configService;
  final WalletFromMnemonic _walletFromMnemonic;
  final FirstDrive _firstDrive;

  /// The wallet Sign up made in this session, which gets its first drive
  /// once its owner reaches the app.
  String? _signUpWalletAddress;

  bool ignoreNextWaletSwitch = false;

  /// Stops listening for Wander's account switches when this bloc closes.
  Function()? _forgetWalletSwitch;

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
    } else if (event is LeaveWallet) {
      await _handleLeaveWalletEvent(event, emit);
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
    } else if (event is AnswerUsedArDriveBefore) {
      await _handleAnswerUsedArDriveBefore(event, emit);
    } else if (event is UnlockWithWallet) {
      await _handleUnlockWithWallet(emit);
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

    final ethDeviceWallet = pending.ethDeviceWallet;
    if (ethDeviceWallet != null) {
      try {
        await _signInExistingEthereumAccount(
          emit,
          wallet: pending.wallet,
          ethWallet: ethDeviceWallet,
          derivedEthWallet: pending.derivedEthWallet!,
          password: pending.password,
          previousState: pending.previousState,
          skipDriveCheck: true,
        );
      } catch (e) {
        logger.e('Failed to sign in with the drives locked', e);
        emit(e is AuthenticationGatewayException
            ? GatewayLoginFailure(e, _getGatewayUrl())
            : LoginUnknownFailure(e));
      }
      return;
    }

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
    // The poll can outlast the event: a newer one may have taken the panel.
    if (emit.isDone) return;
    if (walletFound) {
      existingUserFlow = false;
      // Every way in (the Sign up button, Log in's link, the get-started
      // link) reports the panel here, once.
      PlausibleEventTracker.trackPageview(page: PlausiblePageView.signUpPage);
      emit(_logInPanel);
    } else {
      await _handleCreateNewWalletEvent(
          const CreateNewWallet(), emit);
    }
  }

  /// Shows the panel that waits on [wallet] and returns what Cancel
  /// completes.
  Completer<void> _askWallet(
    Emitter<LoginState> emit,
    BrowserWallet wallet, {
    BrowserWalletRequest request = BrowserWalletRequest.connect,
  }) {
    final previous = _walletCancel;
    if (previous != null && !previous.isCompleted) previous.complete();
    final cancel = Completer<void>();
    _walletCancel = cancel;
    emit(LoginWaitingOnWallet(wallet: wallet, request: request));
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

    // Welcome back's approval: back to Welcome back, the account untouched.
    final unlocking = _unlockingWith;
    if (unlocking != null) {
      _unlockingWith = null;
      emit(unlocking);
      return;
    }

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

      if (e is ProfileFormatTooNewException) {
        emit(const LoginProfileFromNewerVersion());
        return;
      }

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
    wallet = await _walletFromMnemonic(mnemonic);
    emit(LoginCloseBlockingDialog());

    if (_ethNoRecord) {
      // No record to check the password against (Yes to "Have you used
      // ArDrive with this MetaMask before?"): it is right only if the wallet
      // it derives has ArDrive history. Its missing records go up again.
      final bool hasHistory;
      try {
        // It owns drives, or at least its own verification record: its
        // sign-up posted one from this wallet, even if it made no drive.
        hasHistory = await _arDriveAuth.isExistingUser(wallet) ||
            await _arweaveService
                    .getFirstTxForWallet(await wallet.getAddress()) !=
                null;
      } catch (e) {
        emit(e is AuthenticationGatewayException || e is GraphQLException
            ? GatewayLoginFailure(e, _getGatewayUrl())
            : LoginFailure(e));
        return;
      }
      if (!hasHistory) {
        emit(PromptPassword(
          wallet: event.wallet,
          derivedEthWallet: event.derivedEthWallet,
          sourceWalletAddress: _sourceWalletAddress,
          showWalletCreated: false,
          isPasswordInvalid: true,
          noAccountFound: true,
        ));
        return;
      }
      _ethNoRecord = false;
      _pendingEthereum = null;
      unawaited(_repostV1Records(wallet, derivedEthWallet, fullEntropy));
    } else {
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
    }

    profileType = ProfileType.json;

    emit(LoginLoading());

    await _signInExistingEthereumAccount(
      emit,
      wallet: wallet,
      ethWallet: event.wallet as EthereumWallet,
      derivedEthWallet: derivedEthWallet,
      password: event.password,
      previousState: previousState,
    );
  }

  /// An existing MetaMask account, its password just proven to pick its
  /// wallet: saved on this device under MetaMask's device key, so later
  /// visits need one approval and no password. The password is still its
  /// drive password, so it is tried on its private drives first, with the
  /// soft "didn't open your private drives" check.
  Future<void> _signInExistingEthereumAccount(
    Emitter<LoginState> emit, {
    required Wallet wallet,
    required EthereumWallet ethWallet,
    required EthereumProviderWallet derivedEthWallet,
    required String password,
    required LoginState previousState,
    bool skipDriveCheck = false,
  }) async {
    emit(const LoginShowBlockingDialog(
        message: 'Please approve the request in your Ethereum wallet.'));
    try {
      final user = await _loginWithWallet(
        wallet,
        ProfileType.json,
        EthereumDeviceSecret(ethWallet),
        password: password,
        skipDriveCheck: skipDriveCheck,
      );
      emit(LoginCloseBlockingDialog());
      emit(LoginSuccess(user));
    } on PasswordOpensNoDriveException {
      emit(LoginCloseBlockingDialog());
      _pendingSignIn = _PendingSignIn(
        wallet: wallet,
        password: password,
        profileType: ProfileType.json,
        previousState: previousState,
        mnemonic: null,
        isNewUser: false,
        showWalletCreated: false,
        promptWallet: ethWallet,
        derivedEthWallet: derivedEthWallet,
        ethDeviceWallet: ethWallet,
      );
      emit(const LoginPasswordOpensNoDrives());
    } on DeviceUnlockRefusedException catch (e) {
      emit(LoginCloseBlockingDialog());
      emit(_logInPanel);
      if (e.status != DeviceUnlockStatus.declined) emit(LoginFailure(e));
    } catch (_) {
      emit(LoginCloseBlockingDialog());
      rethrow;
    }
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

    final record =
        await _arweaveService.findEthereumAccountRecord(arweaveNativeAddressForEth);
    final String? ethFirstTxId = switch (record) {
      EthereumV1Record(:final txId) => txId,
      EthereumV2Marker(:final laterV1RecordId) => laterV1RecordId,
      null => null,
    };

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

      // An account a browser wallet opens: one approval, never a password,
      // and never asked before the person presses Continue (no wallet call
      // at startup).
      final prompt = await _walletUnlockPrompt();
      if (prompt != null) {
        emit(prompt);
        return;
      }

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

      if (e is ProfileFormatTooNewException) {
        emit(const LoginProfileFromNewerVersion());
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
      // MetaMask accounts no longer choose a password: a new one has none
      // (see [_signInEthereumV2]). Making a password-derived one,
      // with its verification records, was retired in 3.0.
      await _handleCreateArweavePassword(event, emit, previousState);

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

    // 2. One approval, for this device's key. No password and no drive
    // check: private drives open from what this device remembers, or with
    // Unlock (the 3.0 password design).
    final unlock = _askWallet(
      emit,
      BrowserWallet.wander,
      request: BrowserWalletRequest.signIn,
    );
    await _signInWithWallet(
      emit,
      cancel: unlock,
      wallet: wallet,
      profileType: ProfileType.arConnect,
      source: WanderDeviceSecret(wallet),
    );
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

    await _resetWalletFlow();

    emit(const LoginLanding());
  }

  Future<void> _handleLeaveWalletEvent(
    LeaveWallet event,
    Emitter<LoginState> emit,
  ) async {
    // Whatever is stored here stays, unless this flow stored it: a returning
    // user's account must survive a sign-up or sign-in they abandon.
    final saved = _savedByThisFlow;
    if (saved != null && await _storedAccountIs(saved)) {
      await _arDriveAuth
          .logout()
          .then((value) => _profileCubit.logoutProfile());
    }

    await _resetWalletFlow();

    emit(event.toLogIn ? _logInPanel : const LoginLanding());
  }

  /// Whether the account stored on this device is [address]. False when
  /// nothing is stored, and when it can't be told: keeping an account is
  /// never the dangerous choice.
  Future<bool> _storedAccountIs(String address) async =>
      await _storedAddress() == address;

  /// The address of the account stored on this device; null when there is
  /// none or it can't be read.
  Future<String?> _storedAddress() async {
    try {
      return await _arDriveAuth.getWalletAddress();
    } catch (e) {
      logger.w('Could not tell whose account is stored here: $e');
      return null;
    }
  }

  /// The address of the account this sign-in or sign-up saved on this
  /// device, while it hasn't finished: a sign-up whose password step failed
  /// after the save. [LeaveWallet] forgets it, and nothing else.
  String? _savedByThisFlow;

  @visibleForTesting
  set savedByThisFlowForTesting(String? address) => _savedByThisFlow = address;

  @override
  void onChange(Change<LoginState> change) {
    super.onChange(change);
    // Signed in: the account is the user's now, not this flow's to forget.
    if (change.nextState is LoginSuccess) _savedByThisFlow = null;
  }

  /// Drops what a sign-in or sign-up held for the wallet it loaded.
  Future<void> _resetWalletFlow() async {
    _savedByThisFlow = null;
    _pendingEthereum = null;
    _ethNoRecord = false;
    usingSeedphrase = false;
    _sourceWalletAddress = null;
    _signUpToRetry = null;
    await _solanaProviderService.disconnect();
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

    final storedBefore = await _storedAddress();
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
      // Saved on this device from here on: a step after this can fail and
      // reopen the password, and leaving then forgets this account only.
      _savedByThisFlow = user.walletAddress;
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
    } catch (_) {
      // login() saves the profile before reading it back, so it can fail
      // with this wallet already stored. Saved by this flow only if it
      // wasn't stored here before.
      final address = await wallet.getAddress();
      if (storedBefore != address && await _storedAddress() == address) {
        _savedByThisFlow = address;
      }
      rethrow;
    }

    if (showWalletCreated) {
      emit(LoginDownloadGeneratedWallet(wallet: wallet, mnemonic: mnemonic));
    } else {
      emit(LoginSuccess(user));
    }
  }

  @override
  Future<void> close() {
    _forgetWalletSwitch?.call();
    return super.close();
  }

  bool _isArConnectWallet() {
    return profileType == ProfileType.arConnect;
  }

  void _listenToWalletChange() {
    if (!_arConnectService.isExtensionPresent()) {
      return;
    }

    _forgetWalletSwitch = onArConnectWalletSwitch(() async {
      if (isClosed) return;
      logger.d('Wallet switch detected on LoginBloc');
      // A saved account is ProfileCubit's to sign out (see
      // ProfileCubit.signOutForOtherWallet); this only covers a Wander
      // sign-in that has not saved one yet.
      if (await _arDriveAuth.isUserLoggedIn()) return;

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

    emit(const LoginCreatingAccount());

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
      const signMessage = ethereumVerifyMessage;

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

    // Which account this is, from the auth key's records: a version 2
    // marker, a version 1 verification record, or, only once every endpoint
    // has said so, none. A lookup that fails is a failure, never "none": a
    // wrong "none" would make an existing account a new, empty one.
    final EthereumAccountRecord? record;
    try {
      record = await _arweaveService
          .findEthereumAccountRecord(arweaveNativeAddressForEth);
    } catch (e) {
      logger.w('Could not look up the MetaMask account: ${e.runtimeType}');
      emit(LoginCloseBlockingDialog());
      emit(_logInPanel);
      emit(const LoginFailure(EthereumAccountLookupFailed()));
      return;
    }

    emit(LoginCloseBlockingDialog());

    switch (record) {
      case EthereumV1Record():
        _ethNoRecord = false;
        emit(PromptPassword(
            wallet: ethWallet,
            derivedEthWallet: derivedEthWallet,
            sourceWalletAddress: _sourceWalletAddress,
            showWalletCreated: false));
      case EthereumV2Marker(
          :final txId,
          :final accountAddress,
          :final laterV1RecordId
        ):
        await _signInEthereumV2(
          emit,
          ethWallet: ethWallet,
          authWallet: derivedEthWallet,
          expectedAddress:
              accountAddress ?? await _markerAddressFromData(txId),
          passwordAccountToo: laterV1RecordId != null,
        );
      case null:
        // Nothing anywhere: a new account, or one made before 3.0 whose
        // record never reached an index. Only the person knows which.
        _pendingEthereum = (ethWallet, derivedEthWallet);
        emit(const LoginAskUsedMetaMaskBefore());
    }
  }

  /// The MetaMask a "Have you used ArDrive with this MetaMask before?" is
  /// asked for, and its auth key.
  (EthereumWallet, EthereumProviderWallet)? _pendingEthereum;

  /// The password asked for an account with no record found: it is checked
  /// against the wallet's ArDrive history rather than a record. See
  /// [_handleLoginWithEthereumPassword].
  bool _ethNoRecord = false;

  /// "Have you used ArDrive with this MetaMask before?"
  /// - No: a new account, made from the account message signed twice (the
  ///   two must match), with its marker posted.
  /// - Yes: an account made before 3.0 whose record wasn't found. Its
  ///   password is asked, and accepted only if the wallet it derives has
  ///   ArDrive history; its missing records are then posted again.
  Future<void> _handleAnswerUsedArDriveBefore(
    AnswerUsedArDriveBefore event,
    Emitter<LoginState> emit,
  ) async {
    final pending = _pendingEthereum;
    if (pending == null) {
      emit(_logInPanel);
      return;
    }
    final (ethWallet, authWallet) = pending;

    if (event.usedBefore) {
      _ethNoRecord = true;
      emit(_logInPanel);
      emit(PromptPassword(
        wallet: ethWallet,
        derivedEthWallet: authWallet,
        sourceWalletAddress: _sourceWalletAddress,
        showWalletCreated: false,
      ));
      return;
    }

    _pendingEthereum = null;
    await _signInEthereumV2(
      emit,
      ethWallet: ethWallet,
      authWallet: authWallet,
      newAccount: true,
    );
  }

  /// The Arweave address a version 2 marker [txId] holds as its data.
  Future<String?> _markerAddressFromData(String txId) async {
    try {
      final data = await _downloadService.download(txId, false);
      return utf8.decode(data).trim();
    } catch (e) {
      logger.w('Could not read the account marker: ${e.runtimeType}');
      return null;
    }
  }

  /// A version 2 MetaMask account: its wallet comes from a signature of the
  /// fixed [ethereumAccountMessage], with no password, and one more approval
  /// is this device's key. See docs/ArweaveFS.md, "Browser wallet
  /// identities".
  ///
  /// - An existing one ([expectedAddress], from its marker): the wallet
  ///   derived must be that address. A MetaMask that signs differently each
  ///   time (a smart-contract or MPC wallet) derives another one, and is
  ///   refused loudly rather than opening an empty account.
  /// - A new one ([newAccount]): the message is signed twice and the
  ///   signatures must match, for the same reason, and the marker is posted
  ///   before anything is saved here.
  Future<void> _signInEthereumV2(
    Emitter<LoginState> emit, {
    required EthereumWallet ethWallet,
    required EthereumProviderWallet authWallet,
    String? expectedAddress,
    bool newAccount = false,
    bool passwordAccountToo = false,
  }) async {
    if (!newAccount && expectedAddress == null) {
      emit(_logInPanel);
      emit(const LoginFailure(EthereumAccountMarkerUnreadable()));
      return;
    }

    final cancel = _askWallet(
      emit,
      BrowserWallet.metamask,
      request: BrowserWalletRequest.signIn,
    );
    final message = Uint8List.fromList(
        utf8.encode(ethereumAccountMessage(await ethWallet.getAddress())));

    final Uint8List signature;
    try {
      signature = await _walletAnswer(cancel, ethWallet.sign(message));
      if (newAccount) {
        final again = await _walletAnswer(cancel, ethWallet.sign(message));
        if (!listEquals(signature, again)) {
          throw const EthereumWalletSignsDifferently();
        }
      }
    } on WalletLoginCancelled {
      return;
    } on EthereumWalletSignsDifferently catch (e) {
      _walletAnswered(cancel);
      emit(_logInPanel);
      emit(LoginFailure(e));
      return;
    } catch (e) {
      // Refused, or the extension failed: back to Log in.
      logger.w('MetaMask did not sign the account message');
      _sourceWalletAddress = null;
      _walletAnswered(cancel);
      emit(_logInPanel);
      return;
    }

    profileType = ProfileType.json;
    final Wallet wallet;
    try {
      wallet = await _walletAnswer(
        cancel,
        deriveMnemonicFromEthereumAccountSignature(signature)
            .then(_walletFromMnemonic),
      );
    } on WalletLoginCancelled {
      return;
    }

    final address = await wallet.getAddress();
    if (!newAccount && address != expectedAddress) {
      _walletAnswered(cancel);
      emit(_logInPanel);
      if (passwordAccountToo) {
        // A password account was made on this auth key after the marker
        // (an old build, after a rollback): its password is the way in.
        _ethNoRecord = false;
        emit(PromptPassword(
          wallet: ethWallet,
          derivedEthWallet: authWallet,
          sourceWalletAddress: _sourceWalletAddress,
          showWalletCreated: false,
        ));
        return;
      }
      emit(const LoginFailure(EthereumWalletSignsDifferently()));
      return;
    }

    if (newAccount) {
      try {
        await _walletAnswer(cancel, _postAccountMarker(authWallet, address));
      } on WalletLoginCancelled {
        return;
      } catch (e) {
        logger.w('Could not post the account marker: ${e.runtimeType}');
        _walletAnswered(cancel);
        emit(_logInPanel);
        emit(LoginFailure(e));
        return;
      }
    }

    // The account-message signature is also this device's key, as Solana's
    // sign-in signature is: no extra approval.
    await _signInWithWallet(
      emit,
      cancel: cancel,
      wallet: wallet,
      profileType: ProfileType.json,
      source: DeviceSecretSource.fromSecret(
          DeviceUnlockMethod.ethereumAccount, signature),
    );
  }

  /// Posts a version 2 account's marker: a free Turbo data item signed by
  /// the auth key, tagged [ethereumAccountMarkerTags], whose data is the
  /// account's Arweave address.
  Future<void> _postAccountMarker(
    EthereumProviderWallet authWallet,
    String arweaveAddress,
  ) async {
    final item = DataItem.withBlobData(
      data: Uint8List.fromList(utf8.encode(arweaveAddress)),
      owner: await authWallet.getOwner(),
    );
    ethereumAccountMarkerTags(arweaveAddress).forEach(item.addTag);
    await item.sign(EthereumSigner(authWallet.credentials));
    await _turboUploadService.postDataItem(dataItem: item, wallet: authWallet);
  }

  /// Posts a version 1 account's verification records again, as its sign-up
  /// did: the Arweave wallet's signature of [fullEntropy], once from that
  /// wallet and once from the auth key. For an account made before 3.0
  /// whose records no index has. Best effort: signing in doesn't wait on it.
  Future<void> _repostV1Records(
    Wallet wallet,
    EthereumProviderWallet authWallet,
    Uint8List fullEntropy,
  ) async {
    try {
      final verifySignature = await wallet.sign(fullEntropy);

      final arweaveItem = DataItem.withBlobData(
        data: verifySignature,
        owner: await wallet.getOwner(),
      );
      await arweaveItem.sign(ArweaveSigner(wallet));
      await _turboUploadService.postDataItem(
          dataItem: arweaveItem, wallet: wallet);

      final authItem = DataItem.withBlobData(
        data: verifySignature,
        owner: await authWallet.getOwner(),
      );
      await authItem.sign(EthereumSigner(authWallet.credentials));
      await _turboUploadService.postDataItem(
          dataItem: authItem, wallet: authWallet);
      logger.i('Posted the missing verification records again');
    } catch (e) {
      logger.w('Could not post the verification records again: '
          '${e.runtimeType}');
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

      // 5. No password and no drive check. The sign-in signature is also
      // this device's key, so there is nothing more to approve.
      final user = await _loginWithWallet(
        wallet,
        ProfileType.json,
        DeviceSecretSource.fromSecret(DeviceUnlockMethod.solana, signature),
      );
      emit(LoginCloseBlockingDialog());
      emit(LoginSuccess(user));
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

  /// The Welcome back an approval is under way for, so Cancel goes back
  /// there.
  PromptWalletUnlock? _unlockingWith;

  /// Welcome back for the saved account, if a browser wallet opens it; null
  /// for an account its password opens.
  Future<PromptWalletUnlock?> _walletUnlockPrompt({
    WalletUnlockProblem? problem,
  }) async {
    final SavedAccount? account;
    try {
      account = await _arDriveAuth.savedAccount();
    } catch (e) {
      logger.w('Could not read the saved account: ${e.runtimeType}');
      return null;
    }
    final method = account?.walletMethod;
    if (account == null || method == null) return null;
    return PromptWalletUnlock(
      wallet: _browserWalletFor(method),
      relocks: account.isLegacyWalletProfile,
      problem: problem,
    );
  }

  BrowserWallet _browserWalletFor(DeviceUnlockMethod method) {
    switch (method) {
      case DeviceUnlockMethod.wander:
        return BrowserWallet.wander;
      case DeviceUnlockMethod.ethereum:
      case DeviceUnlockMethod.ethereumAccount:
        return BrowserWallet.metamask;
      case DeviceUnlockMethod.solana:
      case DeviceUnlockMethod.password:
        final found = _solanaProviderService.detectProviders();
        if (found.hasPhantom && !found.hasSolflare) {
          return BrowserWallet.phantom;
        }
        if (found.hasSolflare && !found.hasPhantom) {
          return BrowserWallet.solflare;
        }
        return BrowserWallet.otherSolana;
    }
  }

  /// Continue on Welcome back for an account a browser wallet opens: the
  /// wallet is connected, checked to be this account, and asked once for
  /// this device's key, which opens the account and the drives it
  /// remembers.
  ///
  /// A profile saved before 3.0 under a password (Wander, Phantom, Solflare)
  /// is replaced by one the wallet opens; the drive keys it remembered go,
  /// and those drives start locked ([ArDriveAuth.loginWithWallet]).
  Future<void> _handleUnlockWithWallet(Emitter<LoginState> emit) async {
    final account = await _arDriveAuth.savedAccount();
    final method = account?.walletMethod;
    final prompt = await _walletUnlockPrompt();
    if (account == null || method == null || prompt == null) {
      emit(const LoginLanding());
      return;
    }

    final cancel = _askWallet(
      emit,
      prompt.wallet,
      request: BrowserWalletRequest.openDrives,
    );
    _unlockingWith = prompt;

    void problem(WalletUnlockProblem problem) {
      _walletAnswered(cancel);
      _unlockingWith = null;
      emit(prompt.withProblem(problem));
    }

    try {
      final User user;
      switch (method) {
        case DeviceUnlockMethod.wander:
          final wallet =
              await _connectSavedWander(cancel, account, onOtherAccount: () {
            problem(WalletUnlockProblem.otherAccount);
          });
          if (wallet == null) return;
          final source = _CancellableSecret(WanderDeviceSecret(wallet), cancel);
          user = account.isLegacyWalletProfile
              ? await _arDriveAuth.loginWithWallet(
                  wallet, ProfileType.arConnect, source)
              : await _arDriveAuth.unlockWithWallet(source);
          profileType = ProfileType.arConnect;
          lastKnownWalletAddress = account.address;
        case DeviceUnlockMethod.solana:
          final provider = switch (prompt.wallet) {
            BrowserWallet.phantom => 'phantom',
            BrowserWallet.solflare => 'solflare',
            _ => null,
          };
          final connection = await _walletAnswer(
              cancel, _solanaProviderService.connect(provider: provider));
          if (connection == null) {
            // Said no to connecting.
            problem(WalletUnlockProblem.declined);
            return;
          }
          if (connection.address != account.sourceWalletAddress) {
            problem(WalletUnlockProblem.otherAccount);
            return;
          }
          final signature = await _walletAnswer(cancel,
              _solanaProviderService.signMessage(solanaIdentityMessage));
          final source = DeviceSecretSource.fromSecret(
              DeviceUnlockMethod.solana, signature);
          if (account.isLegacyWalletProfile) {
            final wallet = await _walletAnswer(
              cancel,
              deriveMnemonicFromSolanaSignature(signature)
                  .then(_walletFromMnemonic),
            );
            // The profile from before 3.0 is replaced only by the account it
            // holds: another one (a wallet that signs differently, say)
            // would delete what may be its only copy.
            if (await wallet.getAddress() != account.address) {
              problem(WalletUnlockProblem.notThisAccount);
              return;
            }
            user = await _arDriveAuth.loginWithWallet(
              wallet,
              ProfileType.json,
              source,
              sourceWalletAddress: connection.address,
            );
          } else {
            user = await _arDriveAuth.unlockWithWallet(source);
          }
          profileType = ProfileType.json;
        case DeviceUnlockMethod.ethereum:
        case DeviceUnlockMethod.ethereumAccount:
          final ethWallet =
              await _walletAnswer(cancel, _ethereumProviderService.connect());
          final address = ethWallet == null
              ? null
              : await _walletAnswer(cancel, ethWallet.getAddress());
          if (ethWallet == null ||
              address?.toLowerCase() !=
                  account.sourceWalletAddress?.toLowerCase()) {
            problem(WalletUnlockProblem.otherAccount);
            return;
          }
          final DeviceSecretSource source;
          if (method == DeviceUnlockMethod.ethereumAccount) {
            // A version 2 account: its account message, the signature its
            // wallet comes from, is also its device key.
            final signature = await _walletAnswer(
              cancel,
              ethWallet.sign(Uint8List.fromList(
                  utf8.encode(ethereumAccountMessage(address!)))),
            );
            source = DeviceSecretSource.fromSecret(
                DeviceUnlockMethod.ethereumAccount, signature);
          } else {
            source = _CancellableSecret(EthereumDeviceSecret(ethWallet), cancel);
          }
          user = await _arDriveAuth.unlockWithWallet(source);
          profileType = ProfileType.json;
        case DeviceUnlockMethod.password:
          // Not a wallet's: [SavedAccount.walletMethod] never says this.
          return;
      }
      _walletAnswered(cancel);
      _unlockingWith = null;
      emit(LoginSuccess(user));
    } on WalletLoginCancelled {
      return;
    } on DeviceUnlockRefusedException catch (e) {
      if (cancel.isCompleted) return;
      problem(switch (e.status) {
        DeviceUnlockStatus.declined => WalletUnlockProblem.declined,
        DeviceUnlockStatus.mismatch => WalletUnlockProblem.mismatch,
        _ => WalletUnlockProblem.failed,
      });
    } catch (e) {
      if (cancel.isCompleted) return;
      logger.w('Could not open the saved account with its wallet: '
          '${e.runtimeType}');
      if (e is ProfileFormatTooNewException) {
        _walletAnswered(cancel);
        _unlockingWith = null;
        emit(const LoginProfileFromNewerVersion());
        return;
      }
      problem(WalletUnlockProblem.failed);
    }
  }

  /// Wander, connected and on the saved account, as the wallet that signs
  /// for it. Null after [onOtherAccount] when Wander is on another account,
  /// or when it said no to connecting.
  Future<ArConnectWallet?> _connectSavedWander(
    Completer<void> cancel,
    SavedAccount account, {
    required VoidCallback onOtherAccount,
  }) async {
    if (!await _walletAnswer(
        cancel, _arConnectService.isWalletVersionSupported())) {
      throw const ArConnectVersionNotSupportedException();
    }
    var permitted =
        await _walletAnswer(cancel, _arConnectService.checkPermissions());
    if (!permitted) {
      ignoreNextWaletSwitch = true;
      try {
        await _walletAnswer(cancel, _arConnectService.connect());
      } on WalletLoginCancelled {
        rethrow;
      } catch (_) {
        // Said no: nothing more is asked.
      } finally {
        ignoreNextWaletSwitch = false;
      }
      permitted =
          await _walletAnswer(cancel, _arConnectService.checkPermissions());
      if (!permitted) {
        throw const DeviceUnlockRefusedException(DeviceUnlockStatus.declined);
      }
    }
    final address =
        await _walletAnswer(cancel, _arConnectService.getWalletAddress());
    if (address != account.address) {
      onOtherAccount();
      return null;
    }
    // Knows its key, so it asks Wander only to sign.
    return ArConnectWallet(_arConnectService, publicKey: account.publicKey);
  }

  /// [ArDriveAuth.loginWithWallet], noting what this flow saved on this
  /// device, as [LeaveWallet] needs.
  Future<User> _loginWithWallet(
    Wallet wallet,
    ProfileType profileType,
    DeviceSecretSource source, {
    String password = '',
    bool skipDriveCheck = false,
  }) async {
    final storedBefore = await _storedAddress();
    try {
      final user = await _arDriveAuth.loginWithWallet(
        wallet,
        profileType,
        source,
        sourceWalletAddress: _sourceWalletAddress,
        password: password,
        skipDriveCheck: skipDriveCheck,
      );
      _savedByThisFlow = user.walletAddress;
      return user;
    } catch (_) {
      // Saved by this flow only if it wasn't stored here before.
      final address = await wallet.getAddress();
      if (storedBefore != address && await _storedAddress() == address) {
        _savedByThisFlow = address;
      }
      rethrow;
    }
  }

  /// Signs in an account a browser wallet opens, with no password, while
  /// the panel waits on the wallet's one approval for this device's key.
  /// Cancel ([cancel]) ends the wait and saves nothing.
  Future<void> _signInWithWallet(
    Emitter<LoginState> emit, {
    required Completer<void> cancel,
    required Wallet wallet,
    required ProfileType profileType,
    required DeviceSecretSource source,
  }) async {
    try {
      final user = await _loginWithWallet(
        wallet,
        profileType,
        _CancellableSecret(source, cancel),
      );
      _walletAnswered(cancel);
      emit(LoginSuccess(user));
    } on DeviceUnlockRefusedException catch (e) {
      // After Cancel the panel is back at Log in already.
      if (cancel.isCompleted) return;
      _walletAnswered(cancel);
      ignoreNextWaletSwitch = false;
      emit(_logInPanel);
      // Saying no to the wallet is not an error.
      if (e.status != DeviceUnlockStatus.declined) emit(LoginFailure(e));
    } catch (e) {
      if (cancel.isCompleted) return;
      _walletAnswered(cancel);
      ignoreNextWaletSwitch = false;
      emit(_logInPanel);
      emit(e is AuthenticationGatewayException
          ? GatewayLoginFailure(e, _getGatewayUrl())
          : LoginFailure(e));
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
    this.ethDeviceWallet,
  });

  /// An existing MetaMask account: saved under MetaMask's device key, which
  /// this wallet gives, rather than under the password.
  final EthereumWallet? ethDeviceWallet;

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

/// A device secret that gives up when Cancel is pressed: the wait ends as
/// if the person had said no to the wallet, and nothing is saved.
class _CancellableSecret implements DeviceSecretSource {
  _CancellableSecret(this._inner, this._cancel);

  final DeviceSecretSource _inner;
  final Completer<void> _cancel;

  @override
  DeviceUnlockMethod get method => _inner.method;

  @override
  Future<Uint8List> secret(Uint8List deviceSalt) async {
    if (_cancel.isCompleted) throw const DeviceUnlockDeclined();
    final answer = await Future.any<Uint8List?>([
      _inner.secret(deviceSalt),
      _cancel.future.then((_) => null),
    ]);
    if (answer == null || _cancel.isCompleted) {
      throw const DeviceUnlockDeclined();
    }
    return answer;
  }
}

/// A MetaMask signed the account message differently from one time to the
/// next (a smart-contract or MPC wallet), or differently than when its
/// account was made. ArDrive can't make or open an account from it: the
/// wallet would be another, empty one each time.
class EthereumWalletSignsDifferently implements UntrackedException {
  const EthereumWalletSignsDifferently();
}

/// A version 2 MetaMask account's marker was found, but the Arweave address
/// it holds couldn't be read, so the wallet derived can't be checked.
class EthereumAccountMarkerUnreadable implements UntrackedException {
  const EthereumAccountMarkerUnreadable();
}

/// A MetaMask account's records couldn't be read on every index they must
/// be checked on. Never taken for "no account".
class EthereumAccountLookupFailed implements UntrackedException {
  const EthereumAccountLookupFailed();
}
