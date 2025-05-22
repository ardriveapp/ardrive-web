import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/blocking_modals.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/login/views/modals/secure_your_wallet_modal.dart';
import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive/authentication/login/views/tutorials_view.dart';
import 'package:ardrive/authentication/login/views/wallet_created_view.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/icon_theme_switcher.dart';
import 'package:ardrive/components/progress_dialog.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../components/fadethrough_transition_switcher.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';
import 'landing_view.dart';
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
            showProgressDialog(
              context,
              title: 'Loading wallet details...',
              useNewArDriveUI: true,
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
            );
            return;
          } else if (loginState is CreateNewPassword) {
            showSecureYourPasswordDialog(
                context: context,
                loginBloc: context.read<LoginBloc>(),
                wallet: loginState.wallet,
                mnemonic: loginState.mnemonic,
                showTutorials: loginState.showTutorials,
                showWalletCreated: loginState.showWalletCreated,
                derivedEthWallet: loginState.derivedEthWallet);
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
          } else if (loginState is LoginTutorials) {
            preCacheOnBoardingAssets(context);
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
                    'This version of Wander is not supported. Please upgrade and try again.',
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
                  'Oops, something went wrong. Please try again later. If the issue persists, tap the \'Copy Logs\' button to help us diagnose the problem.',
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
                  'There was a problem communicating with the gateway at ${loginState.gatewayUrl}.\nPlease try again later.',
            );
          } else if (loginState
              is LoginPasswordFailedWithPrivateDriveNotFound) {
            showErrorDialog(
              context: context,
              title: appLocalizationsOf(context).loginFailed,
              message:
                  'Your drive is still processing on Arweave. Please wait a few minutes for the transaction to confirm, then try again.',
            );
          }
        },
        buildWhen: (previous, current) {
          return current is! LoginCreatePasswordComplete;
        },
        builder: (context, loginState) {
          late Widget view;
          if (loginState is LoginTutorials) {
            view = TutorialsView(
                wallet: loginState.wallet,
                mnemonic: loginState.mnemonic,
                showWalletCreated: loginState.showWalletCreated);
          } else if (loginState is LoginDownloadGeneratedWallet) {
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
          child: CircularProgressIndicator(),
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
      tablet: (context) => _TabletView(
        globalKey: globalKey,
        loginState: widget.loginState,
      ),
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
                          const Positioned(
                            right: 24,
                            top: 24,
                            child: IconThemeSwitcher(),
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
                          const Positioned(
                            right: 24,
                            top: 24,
                            child: IconThemeSwitcher(),
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

class _TabletView extends StatelessWidget {
  final GlobalKey globalKey;
  final LoginState loginState;

  const _TabletView({
    required this.globalKey,
    required this.loginState,
  });

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;

    return Material(
      color: ArDriveTheme.of(context).themeData.backgroundColor,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                height: 266,
                child: TilesView(),
              ),
            ),
            SizedBox(
              height: height < 1096 ? 800 : height - 298,
              child: _roundedBorderContainer(
                context: context,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Stack(
                  children: [
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
                        child: _buildContent(
                          context,
                          loginState: loginState,
                          globalKey: globalKey,
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 24,
                      top: 24,
                      child: IconThemeSwitcher(),
                    ),
                  ],
                ),
              ),
            ),
          ],
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
            child: _roundedBorderContainer(
              context: context,
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
              child: SizedBox(
                width: constraints.maxWidth,
                height: 300,
                child: Stack(
                  children: [
                    Center(
                      child: _buildContent(
                        context,
                        loginState: loginState,
                        globalKey: globalKey,
                      ),
                    ),
                    const Positioned(
                      right: 0,
                      top: 0,
                      child: IconThemeSwitcher(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

Widget _buildContent(
  BuildContext context, {
  required LoginState loginState,
  required GlobalKey globalKey,
}) {
  return BlocBuilder<LoginBloc, LoginState>(
    key: globalKey,
    buildWhen: (previous, current) {
      final isFailure = current is LoginFailure;
      final isSuccess = current is LoginSuccess;
      final isOnBoarding = current is LoginTutorials;
      final isLoading = current is LoginLoading ||
          current is LoginShowLoader ||
          current is LoginCloseBlockingDialog;
      final isPasswordChecking =
          current is LoginCheckingPassword || current is LoginPasswordFailed;
      final isLoadingIfUserAlreadyExists =
          current is LoginLoadingIfUserAlreadyExists ||
              current is LoginLoadingIfUserAlreadyExistsSuccess;

      return !(isFailure ||
          isSuccess ||
          isOnBoarding ||
          isLoading ||
          isPasswordChecking ||
          isLoadingIfUserAlreadyExists);
    },
    builder: (context, loginState) {
      late Widget content;
      final loginBloc = context.read<LoginBloc>();

      if (loginState is LoginLoading || loginState is LoginSuccess) {
        content = const MaxDeviceSizesConstrainedBox(
          child: LoginCard(
            content: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
      } else if (loginState is LoginLanding) {
        content = const LandingView(
          key: Key('landingPageView'),
        );
      } else {
        content = PromptWalletView(
          key: const Key('promptWalletView'),
          isArConnectAvailable: loginBloc.isArConnectAvailable,
          isMetamaskAvailable: loginBloc.isMetamaskAvailable,
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
