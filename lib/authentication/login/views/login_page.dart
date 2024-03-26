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
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    final arweaveService = context.read<ArweaveService>();
    final downloadService = DownloadService(arweaveService);

    final loginBloc = LoginBloc(
      arConnectService: ArConnectService(),
      ethereumProviderService: EthereumProviderService(),
      turboUploadService: context.read<TurboUploadService>(),
      arweaveService: arweaveService,
      downloadService: downloadService,
      arDriveAuth: context.read<ArDriveAuth>(),
      userRepository: context.read<UserRepository>(),
    )..add(
        CheckIfUserIsLoggedIn(
          gettingStarted: widget.gettingStarted,
        ),
      );

    return BlocProvider<LoginBloc>(
      create: (context) => loginBloc,
      child: BlocConsumer<LoginBloc, LoginState>(
        listener: (context, loginState) {
          if (loginState is! LoginLoading && loginState is! LoginInitial) {
            setState(() {
              didGettingStartedLoadedAlready = true;
            });
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
            }

            showErrorDialog(
              context: context,
              title: appLocalizationsOf(context).loginFailed,
              message: appLocalizationsOf(context).pleaseTryAgain,
            );
          } else if (loginState is LoginSuccess) {
            final profileType = loginState.user.profileType;
            logger.d('Login Success, unlocking default profile');

            context.read<ProfileCubit>().unlockDefaultProfile(
                  loginState.user.password,
                  profileType,
                );
          }
        },
        builder: (context, loginState) {
          late Widget view;
          if (loginState is LoginTutorials) {
            view = TutorialsView(
                wallet: loginState.wallet,
                mnemonic: loginState.mnemonic,
                showWalletCreated: loginState.showWalletCreated);
            // view = TutorialsView(
            //     wallet: Wallet(),
            //     mnemonic: 'test 1 2 3',
            //     showWalletCreated: true);
          } else if (loginState is LoginDownloadGeneratedWallet) {
            view = WalletCreatedView(
                mnemonic: loginState.mnemonic, wallet: loginState.wallet);
            // view = WalletCreatedView(mnemonic: 'test 1 2 3', wallet: Wallet());
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

    final height = MediaQuery.of(context).size.height;

    return BreakpointLayoutBuilder(
      largeDesktop: (context) => Material(
        color: ArDriveTheme.of(context).themeData.backgroundColor,
        child: SizedBox.expand(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                height: height.clamp(800, 1024),
                constraints: const BoxConstraints(
                  maxWidth: 1440,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: _roundedBorderContainer(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                      child: const TilesView(),
                    )),
                    Expanded(
                      child: _roundedBorderContainer(
                          padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                          child: Center(
                              child: SizedBox(
                            width: 381,
                            child: _buildContent(
                              context,
                              loginState: widget.loginState,
                            ),
                          ))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      smallDesktop: (context) => Material(
        color: ArDriveTheme.of(context).themeData.backgroundColor,
        child: SizedBox.expand(
          child: Center(
            child: SingleChildScrollView(
              child: SizedBox(
                height: height.clamp(800, 832),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                        child: _roundedBorderContainer(
                      padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                      child: const TilesView(),
                    )),
                    Expanded(
                      child: _roundedBorderContainer(
                          padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
                          child: Center(
                              child: SizedBox(
                            width: 381,
                            child: _buildContent(
                              context,
                              loginState: widget.loginState,
                            ),
                          ))),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      tablet: (context) => Material(
        color: ArDriveTheme.of(context).themeData.backgroundColor,
        child: SingleChildScrollView(
          child: SizedBox(
            height: 1094,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _roundedBorderContainer(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: const SizedBox(height: 266, child: TilesView()),
                ),
                Container(
                  constraints: const BoxConstraints(
                    minHeight: 800,
                  ),
                  child: _roundedBorderContainer(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: Center(
                        child: SizedBox(
                            width: 381,
                            child: Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(0, 16, 0, 16),
                                child: _buildContent(
                                  context,
                                  loginState: widget.loginState,
                                ))),
                      )),
                ),
              ],
            ),
          ),
        ),
      ),
      phone: (context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: SizedBox.expand(
          child: Center(
            child: SingleChildScrollView(
              child: SizedBox(
                height: height < 600 ? 600 : height,
                child: _roundedBorderContainer(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildContent(
                              context,
                              loginState: widget.loginState,
                            )
                          ]),
                    )),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Widget _buildIllustration(BuildContext context, String image) {
  //   return Stack(
  //     fit: StackFit.expand,
  //     children: [
  //       Opacity(
  //         opacity: 1,
  //         child: Stack(
  //           fit: StackFit.expand,
  //           children: [
  //             ArDriveImage(
  //               key: const Key('loginPageIllustration'),
  //               image: AssetImage(
  //                 image,
  //               ),
  //               height: 600,
  //               width: 600,
  //               fit: BoxFit.cover,
  //             ),
  //             Container(
  //               color: ArDriveTheme.of(context)
  //                   .themeData
  //                   .colors
  //                   .themeBgCanvas
  //                   .withOpacity(0.8),
  //             ),
  //           ],
  //         ),
  //       ),
  //       Center(
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           mainAxisSize: MainAxisSize.min,
  //           children: [
  //             ArDriveImage(
  //               image: AssetImage(
  //                 ArDriveTheme.of(context).themeData.name == 'light'
  //                     ? Resources.images.brand.blackLogo2
  //                     : Resources.images.brand.whiteLogo2,
  //               ),
  //               height: 65,
  //               fit: BoxFit.contain,
  //             ),
  //             Padding(
  //               padding: const EdgeInsets.only(top: 42),
  //               child: SizedBox(
  //                 width: MediaQuery.of(context).size.width * 0.32,
  //                 child: Text(
  //                   appLocalizationsOf(context)
  //                       .yourPrivateSecureAndPermanentDrive,
  //                   textAlign: TextAlign.start,
  //                   style: ArDriveTypography.headline.headline3Regular(
  //                     color: ArDriveTheme.of(context)
  //                         .themeData
  //                         .colors
  //                         .themeFgDefault,
  //                   ),
  //                 ),
  //               ),
  //             ),
  //           ],
  //         ),
  //       )
  //     ],
  //   );
  // }

  Widget _buildContent(BuildContext context, {required LoginState loginState}) {
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

        return !(isFailure ||
            isSuccess ||
            isOnBoarding ||
            isLoading ||
            isPasswordChecking);
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

  Widget _roundedBorderContainer(
      {required Widget child, required EdgeInsetsGeometry padding}) {
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
}
