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
import 'landing_view.dart';
import 'recovery_phrase_view.dart';
import 'modals/enter_your_password_modal.dart';
import 'prompt_wallet_view.dart';

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
          if (loginState is! LoginLoading && loginState is! LoginInitial) {
            setState(() {
              didGettingStartedLoadedAlready = true;
            });
          }

          if (loginState is LoginLoadingIfUserAlreadyExists) {
            showArDriveDialog(
              context,
              barrierDismissible: false,
              content: ProgressDialog(
                title: 'Loading wallet details...',
                progressDescription: Text(
                  'This may take a moment.',
                  style: ArDriveTypographyNew.of(context).paragraphNormal(
                    color:
                        ArDriveTheme.of(context).themeData.colorTokens.textLow,
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
            logger.setContext(logger.context
                .copyWith(userAddress: loginState.user.walletAddress));
            context.read<ProfileNameBloc>().add(LoadProfileName());
          }

          if (loginState is PromptPassword) {
            showEnterYourPasswordDialog(
              context: context,
              loginBloc: context.read<LoginBloc>(),
              wallet: loginState.wallet,
              derivedEthWallet: loginState.derivedEthWallet,
              alreadyLoggedIn: loginState.alreadyLoggedIn,
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
                derivedEthWallet: loginState.derivedEthWallet,
                sourceWalletAddress: loginState.sourceWalletAddress);
            return;
          } else if (loginState is LoginShowLoader) {
            showLoaderDialog(context: context);
            return;
          } else if (loginState is LoginShowBlockingDialog) {
            showBlockingMessageDialog(
                context: context, message: loginState.message);
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
            } else if (loginState.error
                is ArConnectVersionNotSupportedException) {
              showErrorDialog(
                context: context,
                title: appLocalizationsOf(context).loginFailed,
                message:
                    'Your Arweave wallet extension needs to be updated. Please upgrade and try again.',
              );
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
          } else if (loginState
              is LoginPasswordFailedWithPrivateDriveNotFound) {
            showErrorDialog(
              context: context,
              title: appLocalizationsOf(context).loginFailed,
              message:
                  'Your drive is still being confirmed. Please wait a few minutes and try again.',
            );
          }
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

class _LargeDesktopView extends StatelessWidget {
  final LoginState loginState;
  final GlobalKey globalKey;

  const _LargeDesktopView({
    required this.loginState,
    required this.globalKey,
  });

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Material(
      color: ArDriveTheme.of(context).themeData.backgroundColor,
      child: SizedBox.expand(
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              height: height.clamp(832, 1024),
              constraints: const BoxConstraints(
                maxWidth: 1440,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, 8, 0, 8),
                      child: TilesView(),
                    ),
                  ),
                  Expanded(
                    child: _roundedBorderContainer(
                      context: context,
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
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
            child: SizedBox(
              height: 832,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(8, 8, 0, 8),
                      child: TilesView(),
                    ),
                  ),
                  Expanded(
                    child: _roundedBorderContainer(
                      context: context,
                      padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
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
                    child: Stack(
                      children: [
                        Center(
                          child: _buildContent(
                            context,
                            loginState: loginState,
                            globalKey: globalKey,
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
                // The whole bento, after the panel: on a phone the way in
                // comes first.
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: TilesView(),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Whether the sign-in panel redraws for [current]. Dialogs, loaders and
/// transient states leave the panel as it is.
@visibleForTesting
bool loginPanelRebuildsOn(LoginState current) {
  final isFailure = current is LoginFailure;
  final isSuccess = current is LoginSuccess;
  final isLoading = current is LoginLoading ||
      current is LoginShowLoader ||
      current is LoginCloseBlockingDialog;
  final isPasswordChecking =
      current is LoginCheckingPassword || current is LoginPasswordFailed;
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
    builder: (context, loginState) {
      late Widget content;
      final loginBloc = context.read<LoginBloc>();

      if (loginState is LoginSuccess) {
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
        content = const CreatingAccountView(key: Key('creatingAccountView'));
      } else if (loginState is LoginLoading || loginState is LoginLanding) {
        content = const LandingView(
          key: Key('landingPageView'),
        );
      } else {
        content = PromptWalletView(
          key: const Key('promptWalletView'),
          isArConnectAvailable: loginBloc.isArConnectAvailable,
          isMetamaskAvailable: loginBloc.isMetamaskAvailable,
          isSolanaAvailable: loginBloc.isSolanaAvailable,
          existingUserFlow: loginBloc.existingUserFlow,
        );
      }

      return content;
    },
  );
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
