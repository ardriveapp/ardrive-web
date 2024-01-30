import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/create_new_wallet_view.dart';
import 'package:ardrive/authentication/login/views/enter_seed_phrase_view.dart';
import 'package:ardrive/authentication/login/views/generate_wallet_view.dart';
import 'package:ardrive/authentication/login/views/tiles/tiles_view.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/components/app_version_widget.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/user/repositories/user_repository.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../components/fadethrough_transition_switcher.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';
import 'create_password_view.dart';
import 'download_wallet_view.dart';
import 'landing_page.dart';
import 'modals/enter_your_password_modal.dart';
import 'onboarding_view.dart';
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
    final loginBloc = LoginBloc(
      arConnectService: ArConnectService(),
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
                wallet: loginState.walletFile);
            return;
          } else if (loginState is LoginOnBoarding) {
            preCacheOnBoardingAssets(context);
          } else if (loginState is LoginFailure) {
            // TODO: Verify if the error is `NoConnectionException` and show an
            /// appropriate message after validating with UI/UX
            if (loginState.error is WalletMismatchException) {
              showArDriveDialog(
                context,
                content: ArDriveIconModal(
                  title: appLocalizationsOf(context).loginFailed,
                  content: appLocalizationsOf(context)
                      .arConnectWalletDoestNotMatchArDriveWallet,
                  icon: ArDriveIcons.triangle(
                    size: 88,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeErrorMuted,
                  ),
                ),
              );
              return;
            } else if (loginState.error is BiometricException) {
              showBiometricExceptionDialogForException(
                  context, loginState.error as BiometricException, () {});
              return;
            }

            showArDriveDialog(
              context,
              content: ArDriveIconModal(
                title: appLocalizationsOf(context).loginFailed,
                content: appLocalizationsOf(context).pleaseTryAgain,
                icon: ArDriveIcons.triangle(
                  size: 88,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
                ),
              ),
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
          if (loginState is LoginOnBoarding) {
            view = OnBoardingView(wallet: loginState.walletFile);
          } else if (loginState is LoginCreateNewWallet) {
            view = CreateNewWalletView(mnemonic: loginState.mnemonic);
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

    return ScreenTypeLayout.builder(
      desktop: (context) => Material(
        color: ArDriveTheme.of(context).themeData.backgroundColor,
        child: Row(
          children: [
            Expanded(
              child: Stack(
                children: [
                  const TilesView(),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    child: AppVersionWidget(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: 0.75,
                child: Center(
                  child: _buildContent(
                    context,
                    loginState: widget.loginState,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      mobile: (context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            child: Stack(
              children: [
                Center(
                  child: Column(
                    children: [
                      _buildContent(
                        context,
                        loginState: widget.loginState,
                      ),
                    ],
                  ),
                ),
                Positioned(
                  bottom: 16,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width - 32,
                    child: AppVersionWidget(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                ),
              ],
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
    final enableSeedPhraseLogin =
        context.read<ConfigService>().config.enableSeedPhraseLogin;
    return BlocBuilder<LoginBloc, LoginState>(
      key: globalKey,
      buildWhen: (previous, current) {
        final isFailure = current is LoginFailure;
        final isSuccess = current is LoginSuccess;
        final isOnBoarding = current is LoginOnBoarding;
        final isCreateNewWallet = current is LoginCreateNewWallet;

        return !(isFailure || isSuccess || isOnBoarding || isCreateNewWallet);
      },
      builder: (context, loginState) {
        late Widget content;

        if (loginState is PromptPassword) {
          final loginBloc = context.read<LoginBloc>();
          content = PromptWalletView(
            key: const Key('promptWalletView'),
            isArConnectAvailable: loginBloc.isArConnectAvailable,
            existingUserFlow: loginBloc.existingUserFlow,
          );
        } else if (loginState is CreatingNewPassword) {
          content = CreatePasswordView(
            wallet: loginState.walletFile,
          );
        } else if (loginState is LoginLoading || loginState is LoginSuccess) {
          content = const MaxDeviceSizesConstrainedBox(
            child: LoginCard(
              content: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        } else if (enableSeedPhraseLogin &&
            loginState is LoginEnterSeedPhrase) {
          content = const EnterSeedPhraseView();
        } else if (enableSeedPhraseLogin && loginState is LoginGenerateWallet) {
          content = const GenerateWalletView();
        } else if (enableSeedPhraseLogin &&
            loginState is LoginDownloadGeneratedWallet) {
          content = DownloadWalletView(
            mnemonic: loginState.mnemonic,
            wallet: loginState.walletFile,
          );
        } else if (loginState is LoginLanding) {
          content = const LandingPageView(
            key: Key('landingPageView'),
          );
        } else {
          var existingUserFlow = (loginState as LoginInitial).existingUserFlow;
          content = PromptWalletView(
            key: const Key('promptWalletView'),
            isArConnectAvailable: loginState.isArConnectAvailable,
            existingUserFlow: existingUserFlow,
          );
        }

        return SizedBox(
          height: MediaQuery.of(context).size.height,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              content,
            ],
          ),
        );
      },
    );
  }
}
