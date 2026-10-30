import 'dart:math' as math;

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/blocking_modals.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/login/views/modals/secure_your_wallet_modal.dart';
import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive/authentication/login/views/wallet_created_view.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive/components/settings_popover.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider.dart';
import 'package:ardrive/services/solana/solana_provider.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/fadethrough_transition_switcher.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';
import 'creating_account_view.dart';
import 'enter_recovery_phrase_view.dart';
import 'landing_view.dart';
import 'log_in_view.dart';
import 'recovery_phrase_view.dart';
import 'modals/enter_your_password_modal.dart';
import 'wallet_wait_view.dart';
import 'welcome_back_view.dart';

class LoginPage extends StatefulWidget {
  final bool gettingStarted;

  const LoginPage({
    super.key,
    this.gettingStarted = false,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool didGettingStartedLoadedAlready = false;
  bool get isGettingStartedLoading =>
      widget.gettingStarted && !didGettingStartedLoadedAlready;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.welcomePage,
    ).then(
      (value) => PlausibleEventTracker.trackAppLoaded(),
    );

    final arweaveService = context.read<ArweaveService>();
    final downloadService = DownloadService(arweaveService);

    _loginBloc = LoginBloc(
      arConnectService: ArConnectService(),
      ethereumProviderService: EthereumProviderService(),
      solanaProviderService: SolanaProviderService(),
      turboUploadService: context.read<TurboUploadService>(),
      arweaveService: arweaveService,
      downloadService: downloadService,
      arDriveAuth: context.read<ArDriveAuth>(),
      userRepository: context.read<UserRepository>(),
      profileCubit: context.read<ProfileCubit>(),
      configService: context.read<ConfigService>(),
    )..add(
        CheckIfUserIsLoggedIn(
          gettingStarted: widget.gettingStarted,
        ),
      );
  }

  late LoginBloc _loginBloc;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginBloc>(
      create: (context) => _loginBloc,
      child: BlocConsumer<LoginBloc, LoginState>(
        listener: (context, loginState) {
          if (gettingStartedReady(loginState)) {
            setState(() {
              didGettingStartedLoadedAlready = true;
            });
          }

          handleLoginState(context, loginState);
        },
        buildWhen: (previous, current) {
          return current is! LoginCreatePasswordComplete;
        },
        builder: (context, loginState) {
          late Widget view;
          if (loginState is LoginDownloadGeneratedWallet &&
              loginState.mnemonic == null) {
            // Rare: no 12 words to save, only a keyfile.
            view = WalletCreatedView(
                mnemonic: loginState.mnemonic, wallet: loginState.wallet);
          } else {
            view = LoginPageScaffold(
              loginState: loginState,
              isGettingStartedLoading: isGettingStartedLoading,
            );
          }

          return FadeThroughTransitionSwitcher(
            fillColor: Colors.transparent,
            child: view,
          );
        },
      ),
    );
  }
}

class LoginPageScaffold extends StatefulWidget {
  final bool isGettingStartedLoading;
  final LoginState loginState;

  const LoginPageScaffold({
    super.key,
    this.isGettingStartedLoading = false,
    required this.loginState,
  });

  @override
  State<LoginPageScaffold> createState() => _LoginPageScaffoldState();
}

class _LoginPageScaffoldState extends State<LoginPageScaffold> {
  final globalKey = GlobalKey();
  bool getStartedLoadingHasRan = false;

  @override
  Widget build(BuildContext context) {
    if (widget.isGettingStartedLoading) {
      return const Scaffold(
        body: Center(
          child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
        ),
      );
    }

    // TODO: refactor to reduce code repetition
    return BreakpointLayoutBuilder(
      largeDesktop: (context) => _LargeDesktopView(
        loginState: widget.loginState,
        globalKey: globalKey,
      ),
      smallDesktop: (context) => _SmallDesktopView(
        globalKey: globalKey,
        loginState: widget.loginState,
      ),
      // No tablet layout: from the phone breakpoint up the panel and the
      // bento sit side by side, and the bento reflows to its own width
      // rather than dropping tiles.
      phone: (context) => _PhoneView(
        globalKey: globalKey,
        loginState: widget.loginState,
      ),
    );
  }
}

/// The page's outer margin, the same on every side for the bento and the
/// sign-in panel, so their tops and bottoms line up; also the gap between
/// them, the same as the bento's gap between its tiles.
const _pageMargin = 8.0;

/// Side by side, the page is the window's height, between 832 and 1024; a
/// shorter window scrolls it, a taller one centres it.
double _desktopHeight(BuildContext context) =>
    MediaQuery.of(context).size.height.clamp(832, 1024);

class _LargeDesktopView extends StatelessWidget {
  final LoginState loginState;
  final GlobalKey globalKey;

  const _LargeDesktopView({
    required this.loginState,
    required this.globalKey,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ArDriveTheme.of(context).themeData.backgroundColor,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              height: _desktopHeight(context),
              constraints: const BoxConstraints(
                maxWidth: 1440,
              ),
              padding: const EdgeInsets.all(_pageMargin),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: TilesView()),
                  const SizedBox(width: _pageMargin),
                  Expanded(
                    child: _roundedBorderContainer(
                      context: context,
                      padding: EdgeInsets.zero,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: _buildContent(
                              context,
                              loginState: loginState,
                              globalKey: globalKey,
                            ),
                          ),
                          Positioned(
                            right: 24,
                            top: 24,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SettingsSubmenu(
                                  child: ArDriveClickArea(
                                    tooltip: 'Advanced settings',
                                    child: Icon(
                                      Icons.settings,
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colorTokens
                                          .iconLow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const IconThemeSwitcher(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SmallDesktopView extends StatelessWidget {
  final GlobalKey globalKey;
  final LoginState loginState;

  const _SmallDesktopView({
    required this.globalKey,
    required this.loginState,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ArDriveTheme.of(context).themeData.backgroundColor,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              height: _desktopHeight(context),
              padding: const EdgeInsets.all(_pageMargin),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(child: TilesView()),
                  const SizedBox(width: _pageMargin),
                  Expanded(
                    child: _roundedBorderContainer(
                      context: context,
                      padding: EdgeInsets.zero,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: _buildContent(
                              context,
                              loginState: loginState,
                              globalKey: globalKey,
                            ),
                          ),
                          Positioned(
                            right: 24,
                            top: 24,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SettingsSubmenu(
                                  child: ArDriveClickArea(
                                    tooltip: 'Advanced settings',
                                    child: Icon(
                                      Icons.settings,
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colorTokens
                                          .iconLow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const IconThemeSwitcher(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneView extends StatelessWidget {
  const _PhoneView({
    required this.globalKey,
    required this.loginState,
  });

  final GlobalKey globalKey;
  final LoginState loginState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: LayoutBuilder(builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _roundedBorderContainer(
                  context: context,
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                  child: SizedBox(
                    width: constraints.maxWidth,
                    height: math.max(520, constraints.maxHeight - 16),
                    // The panel's own inset, so a step's fields and buttons
                    // don't run into its border.
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Stack(
                        children: [
                          // Scrolls when a step is taller than the panel,
                          // as on a narrow phone with the keyboard up, and
                          // keeps clear of the buttons in the corner.
                          Positioned.fill(
                            child: LayoutBuilder(
                              builder: (context, box) => SingleChildScrollView(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 40),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: math.max(0, box.maxHeight - 80),
                                  ),
                                  child: Center(
                                    child: _buildContent(
                                      context,
                                      loginState: loginState,
                                      globalKey: globalKey,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SettingsSubmenu(
                                  child: ArDriveClickArea(
                                    tooltip: 'Advanced settings',
                                    child: Icon(
                                      Icons.settings,
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colorTokens
                                          .iconLow,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                const IconThemeSwitcher(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // The whole bento, after the panel: on a phone the way in
                // comes first. A step past the first panel takes the whole
                // screen, so the bento is for the first panel only.
                BlocBuilder<LoginBloc, LoginState>(
                  buildWhen: (_, current) => loginPanelRebuildsOn(current),
                  builder: (context, state) =>
                      state is LoginLanding || state is LoginLoading
                          ? const Padding(
                              padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                              child: TilesView(),
                            )
                          : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// What the login page does for [loginState] besides drawing the panel:
/// dialogs, errors and the profile.
@visibleForTesting
void handleLoginState(BuildContext context, LoginState loginState) {
  if (loginState is LoginLoadingIfUserAlreadyExists) {
    showArDriveDialog(
      context,
      barrierDismissible: false,
      content: ProgressDialog(
        title: 'Loading wallet details...',
        progressDescription: Text(
          'This may take a moment.',
          style: ArDriveTypographyNew.of(context).paragraphNormal(
            color: ArDriveTheme.of(context).themeData.colorTokens.textLow,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
      ),
    );

    return;
  }

  if (loginState is LoginLoadingIfUserAlreadyExistsSuccess) {
    Navigator.of(context).pop();
    return;
  }

  if (loginState is LoginSuccess) {
    logger.setContext(
        logger.context.copyWith(userAddress: loginState.user.walletAddress));
    context.read<ProfileNameBloc>().add(LoadProfileName());
  }

  if (loginState is PromptPassword) {
    // The account already on this device is unlocked in the panel,
    // Welcome back; a dialog would cover it.
    final wallet = loginState.wallet;
    if (loginState.alreadyLoggedIn || wallet == null) return;
    showEnterYourPasswordDialog(
      context: context,
      loginBloc: context.read<LoginBloc>(),
      wallet: wallet,
      derivedEthWallet: loginState.derivedEthWallet,
      isPasswordInvalid: loginState.isPasswordInvalid,
      sourceWalletAddress: loginState.sourceWalletAddress,
    );
    return;
  } else if (loginState is CreateNewPassword) {
    showSecureYourPasswordDialog(
        context: context,
        loginBloc: context.read<LoginBloc>(),
        wallet: loginState.wallet,
        mnemonic: loginState.mnemonic,
        isNewUser: loginState.isNewUser,
        showWalletCreated: loginState.showWalletCreated,
        retrying: loginState.retrying,
        fromSignUp: loginState.fromSignUp,
        derivedEthWallet: loginState.derivedEthWallet,
        sourceWalletAddress: loginState.sourceWalletAddress);
    return;
  } else if (loginState is LoginShowLoader) {
    showLoaderDialog(context: context);
    return;
  } else if (loginState is LoginShowBlockingDialog) {
    showBlockingMessageDialog(context: context, message: loginState.message);
    return;
  } else if (loginState is LoginCloseBlockingDialog) {
    Navigator.of(context).pop();
  } else if (loginState is LoginFailure) {
    // TODO: Verify if the error is `NoConnectionException` and show an
    /// appropriate message after validating with UI/UX
    if (loginState.error is WalletMismatchException) {
      showErrorDialog(
        context: context,
        title: appLocalizationsOf(context).loginFailed,
        message: appLocalizationsOf(context)
            .arConnectWalletDoestNotMatchArDriveWallet,
      );
      return;
    } else if (loginState.error is BiometricException) {
      showBiometricExceptionDialogForException(
          context, loginState.error as BiometricException, () {});
      return;
    } else if (loginState.error is ArConnectVersionNotSupportedException) {
      showErrorDialog(
        context: context,
        title: appLocalizationsOf(context).loginFailed,
        message:
            'Your Arweave wallet extension needs to be updated. Please upgrade and try again.',
      );
      return;
    }

    // A new account goes straight back to its password step, for
    // the same wallet, which says what happened. An error dialog
    // here would be closed at once by the password dialog closing.
    final loginBloc = context.read<LoginBloc>();
    if (loginBloc.hasSignUpToRetry) {
      loginBloc.add(const RetrySignUpPassword());
      return;
    }
    showErrorDialog(
      context: context,
      title: appLocalizationsOf(context).loginFailed,
      message: appLocalizationsOf(context).pleaseTryAgain,
    );
  } else if (loginState is LoginUnknownFailure) {
    showErrorDialog(
      context: context,
      title: appLocalizationsOf(context).loginFailed,
      showShareLogsButton: true,
      message:
          'Something went wrong. Please try again. If the issue persists, tap \'Copy Logs\' to help us diagnose the problem.',
    );
  } else if (loginState is LoginSuccess) {
    final profileType = loginState.user.profileType;
    logger.d('Login Success, unlocking default profile');

    context.read<ProfileCubit>().unlockDefaultProfile(
          loginState.user,
          profileType,
        );
  } else if (loginState is GatewayLoginFailure) {
    showErrorDialog(
      context: context,
      title: appLocalizationsOf(context).loginFailed,
      message:
          'Unable to connect to the server. Please check your connection and try again.',
    );
  } else if (loginState is LoginPasswordOpensNoDrives) {
    showPasswordOpensNoDrivesDialog(
      context: context,
      loginBloc: context.read<LoginBloc>(),
    );
  } else if (loginState is LoginPasswordFailedWithPrivateDriveNotFound) {
    showErrorDialog(
      context: context,
      title: appLocalizationsOf(context).loginFailed,
      message:
          'Your drive is still being confirmed. Please wait a few minutes and try again.',
    );
  }
}

/// Whether the get-started link's spinner can give way to the panel: once
/// the check for an account on this device is done. Sign up's choice is a
/// [LoginInitial], so that state no longer means "still loading".
@visibleForTesting
bool gettingStartedReady(LoginState state) => state is! LoginLoading;

/// Whether the sign-in panel redraws for [current]. Dialogs, loaders and
/// transient states leave the panel as it is.
@visibleForTesting
bool loginPanelRebuildsOn(LoginState current) {
  final isFailure = current is LoginFailure ||
      current is LoginUnknownFailure ||
      // Welcome back says this itself, and keeps its place.
      current is LoginProfileFromNewerVersion ||
      current is GatewayLoginFailure ||
      current is LoginPasswordFailedWithPrivateDriveNotFound;
  final isSuccess = current is LoginSuccess;
  final isLoading = current is LoginLoading ||
      current is LoginShowLoader ||
      current is LoginShowBlockingDialog ||
      current is LoginCloseBlockingDialog;
  // A password for a wallet just chosen is asked in a dialog over the panel
  // it was chosen on. Only the account already on this device is unlocked
  // in the panel itself.
  final isPasswordDialog =
      current is PromptPassword && !current.alreadyLoggedIn;
  final isPasswordChecking = current is LoginCheckingPassword ||
      current is LoginPasswordFailed ||
      current is LoginPasswordOpensNoDrives ||
      current is LoginPasswordRetry;
  // The password dialog opens over whatever the panel shows: for a new
  // account, "Creating your account".
  final isChoosingPassword = current is CreateNewPassword;
  // Follows the recovery phrase step; the phrase must stay on screen.
  final isPasswordCreated = current is LoginCreatePasswordComplete;
  final isLoadingIfUserAlreadyExists =
      current is LoginLoadingIfUserAlreadyExists ||
          current is LoginLoadingIfUserAlreadyExistsSuccess;

  return !(isFailure ||
      isSuccess ||
      isLoading ||
      isPasswordDialog ||
      isPasswordChecking ||
      isChoosingPassword ||
      isPasswordCreated ||
      isLoadingIfUserAlreadyExists);
}

Widget _buildContent(
  BuildContext context, {
  required LoginState loginState,
  required GlobalKey globalKey,
}) {
  return BlocBuilder<LoginBloc, LoginState>(
    key: globalKey,
    buildWhen: (previous, current) => loginPanelRebuildsOn(current),
    builder: (context, loginState) =>
        loginPanelFor(loginState, context.read<LoginBloc>()),
  );
}

/// The sign-in panel for [loginState].
@visibleForTesting
Widget loginPanelFor(LoginState loginState, LoginBloc loginBloc) {
  late Widget content;

  if (loginState is PromptPassword && loginState.alreadyLoggedIn) {
    content = const WelcomeBackView(key: Key('welcomeBackView'));
  } else if (loginState is LoginEnterRecoveryPhrase) {
    content = const EnterRecoveryPhraseView(
      key: Key('enterRecoveryPhraseView'),
    );
  } else if (loginState is LoginWaitingOnWallet) {
    content = WalletWaitView(
      key: const Key('walletWaitView'),
      wallet: loginState.wallet,
      request: loginState.request,
    );
  } else if (loginState is LoginSuccess) {
    content = const MaxDeviceSizesConstrainedBox(
      child: LoginCard(
        content: Center(
          child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
        ),
      ),
    );
  } else if (loginState is LoginDownloadGeneratedWallet &&
      loginState.mnemonic != null) {
    content = RecoveryPhraseView(
      key: const Key('recoveryPhraseView'),
      mnemonic: loginState.mnemonic!,
      wallet: loginState.wallet,
    );
  } else if (loginState is LoginCreatingAccount) {
    content = CreatingAccountView(
      key: const Key('creatingAccountView'),
      noWalletFound: loginState.noWalletFound,
    );
  } else if (loginState is LoginLoading || loginState is LoginLanding) {
    content = const LandingView(
      key: Key('landingPageView'),
    );
  } else {
    // Sign up's choice, or Log in. Other states that land here keep the
    // flow the bloc is in.
    final signUp = loginState is LoginInitial
        ? !loginState.existingUserFlow
        : !loginBloc.existingUserFlow;
    content = LogInView(
      key: const Key('logInView'),
      signUp: signUp,
      backToLogIn: signUp && loginBloc.signUpFromLogIn,
      isArConnectAvailable: loginBloc.isArConnectAvailable,
      isMetamaskAvailable: loginBloc.isMetamaskAvailable,
      isSolanaAvailable: loginBloc.isSolanaAvailable,
    );
  }

  return content;
}

Widget _roundedBorderContainer({
  required Widget child,
  required EdgeInsetsGeometry padding,
  required BuildContext context,
}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  return Padding(
    padding: padding,
    child: Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorTokens.strokeLow,
          width: 1,
        ),
      ),
      child: child,
    ),
  );
}
