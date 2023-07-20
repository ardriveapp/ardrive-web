import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:animations/animations.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/blocs/stub_web_wallet.dart' // stub implementation
    if (dart.library.html) 'package:ardrive/authentication/login/blocs/web_wallet.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/profile_auth/components/profile_auth_add_screen.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:responsive_builder/responsive_builder.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  @override
  Widget build(BuildContext context) {
    return BlocProvider<LoginBloc>(
      create: (context) => LoginBloc(
        arConnectService: ArConnectService(),
        arDriveAuth: context.read<ArDriveAuth>(),
      )..add(const CheckIfUserIsLoggedIn()),
      child: BlocConsumer<LoginBloc, LoginState>(
        listener: (context, state) {
          if (state is LoginOnBoarding) {
            preCacheOnBoardingAssets(context);
          }
        },
        builder: (context, state) {
          late Widget view;
          if (state is LoginOnBoarding) {
            view = OnBoardingView(wallet: state.walletFile);
          } else if (state is LoginCreateNewWallet) {
            view = CreateNewWalletView(mnemonic: state.mnemonic);
          } else {
            view = const LoginPageScaffold();
          }

          return _FadeThroughTransitionSwitcher(
            fillColor: Colors.transparent,
            child: view,
          );
        },
      ),
    );
  }
}

class LoginPageScaffold extends StatefulWidget {
  const LoginPageScaffold({
    super.key,
  });

  @override
  State<LoginPageScaffold> createState() => _LoginPageScaffoldState();
}

class _LoginPageScaffoldState extends State<LoginPageScaffold> {
  final globalKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      desktop: (context) => Material(
        color: ArDriveTheme.of(context).themeData.backgroundColor,
        child: Row(
          children: [
            Expanded(
              child: _buildIllustration(
                  context,
                  // verify theme light
                  Resources.images.login.gridImage),
            ),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: 0.75,
                child: Center(
                  child: _buildContent(context),
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
            child: Center(child: _buildContent(context)),
          ),
        ),
      ),
    );
  }

  Widget _buildIllustration(BuildContext context, String image) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              ArDriveImage(
                key: const Key('loginPageIllustration'),
                image: AssetImage(
                  image,
                ),
                height: 600,
                width: 600,
                fit: BoxFit.cover,
              ),
              Container(
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeBgCanvas
                    .withOpacity(0.8),
              ),
            ],
          ),
        ),
        Center(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ArDriveImage(
                image: AssetImage(
                  ArDriveTheme.of(context).themeData.name == 'light'
                      ? Resources.images.brand.blackLogo2
                      : Resources.images.brand.whiteLogo2,
                ),
                height: 65,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 42),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.32,
                  child: Text(
                    appLocalizationsOf(context)
                        .yourPrivateSecureAndPermanentDrive,
                    textAlign: TextAlign.start,
                    style: ArDriveTypography.headline.headline3Regular(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeFgDefault,
                    ),
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final enableSeedPhraseLogin =
        context.read<ConfigService>().config.enableSeedPhraseLogin;
    return BlocConsumer<LoginBloc, LoginState>(
      key: globalKey,
      buildWhen: (previous, current) =>
          current is! LoginFailure &&
          current is! LoginSuccess &&
          current is! LoginOnBoarding &&
          current is! LoginCreateNewWallet,
      listener: (context, state) {
        if (state is LoginFailure) {
          // TODO: Verify if the error is `NoConnectionException` and show an appropriate message after validating with UI/UX

          if (state.error is WalletMismatchException) {
            showAnimatedDialog(
              context,
              content: ArDriveIconModal(
                title: appLocalizationsOf(context).loginFailed,
                content: appLocalizationsOf(context)
                    .arConnectWalletDoestNotMatchArDriveWallet,
                icon: ArDriveIcons.triangle(
                  size: 88,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
                ),
              ),
            );
            return;
          } else if (state.error is BiometricException) {
            showBiometricExceptionDialogForException(
                context, state.error as BiometricException, () {});
            return;
          }

          showAnimatedDialog(
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
        } else if (state is LoginSuccess) {
          context.read<ProfileCubit>().unlockDefaultProfile(
              state.user.password, state.user.profileType);
        }
      },
      builder: (context, state) {
        late Widget content;

        if (state is PromptPassword) {
          content = PromptPasswordView(
            wallet: state.walletFile,
          );
        } else if (state is CreatingNewPassword) {
          content = CreatePasswordView(
            wallet: state.walletFile,
          );
        } else if (state is LoginLoading) {
          content = const MaxDeviceSizesConstrainedBox(
            child: _LoginCard(
              content: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        } else if (enableSeedPhraseLogin && state is LoginEnterSeedPhrase) {
          content = const EnterSeedPhraseView();
        } else if (enableSeedPhraseLogin && state is LoginGenerateWallet) {
          content = const GenerateWalletView();
        } else if (enableSeedPhraseLogin &&
            state is LoginDownloadGeneratedWallet) {
          content = DownloadWalletView(
              mnemonic: state.mnemonic, wallet: state.walletFile);
        } else {
          content = PromptWalletView(
            key: const Key('promptWalletView'),
            isArConnectAvailable: (state as LoginInitial).isArConnectAvailable,
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

class PromptWalletView extends StatefulWidget {
  const PromptWalletView({
    super.key,
    required this.isArConnectAvailable,
  });

  final bool isArConnectAvailable;

  @override
  State<PromptWalletView> createState() => _PromptWalletViewState();
}

class _PromptWalletViewState extends State<PromptWalletView> {
  late ArDriveDropAreaSingleInputController _dropAreaController;

  @override
  void initState() {
    _dropAreaController = ArDriveDropAreaSingleInputController(
      onFileAdded: (file) {
        context.read<LoginBloc>().add(AddWalletFile(file));
      },
      validateFile: (file) async {
        final wallet =
            await context.read<LoginBloc>().validateAndReturnWalletFile(file);

        return wallet != null;
      },
      onDragEntered: () {},
      onDragExited: () {},
      onError: (Object e) {},
    );

    super.initState();
  }

  bool _showSecurityOverlay = false;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return MaxDeviceSizesConstrainedBox(
      defaultMaxWidth: 512,
      defaultMaxHeight: 798,
      maxHeightPercent: 0.9,
      child: SingleChildScrollView(
        child: _LoginCard(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => const SizedBox.shrink(),
                mobile: (context) => ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              heightSpacing(),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  appLocalizationsOf(context).login,
                  style: ArDriveTypography.headline.headline4Regular(),
                ),
              ),
              heightSpacing(),
              Column(
                children: [
                  if (context
                      .read<ConfigService>()
                      .config
                      .enableSeedPhraseLogin) ...[
                    ArDriveButton(
                      icon: ArDriveIcons.keypad(
                          size: 24, color: colors.themeFgDefault),
                      key: const Key('loginWithSeedPhraseButton'),
                      // TODO: create/update localization key
                      text: 'Enter Seed Phrase',
                      onPressed: () {
                        context.read<LoginBloc>().add(const EnterSeedPhrase());
                      },
                      style: ArDriveButtonStyle.secondary,
                      fontStyle: ArDriveTypography.body.smallBold700(
                        color: colors.themeFgDefault,
                      ),
                      maxWidth: double.maxFinite,
                    ),
                    const SizedBox(height: 16),
                  ],
                  ArDriveDropAreaSingleInput(
                    controller: _dropAreaController,
                    keepButtonVisible: true,
                    width: double.maxFinite,
                    // TODO: create/update localization key
                    dragAndDropDescription: 'Select a KeyFile',
                    dragAndDropButtonTitle: 'Select a KeyFile',
                    errorDescription:
                        appLocalizationsOf(context).invalidKeyFile,
                    validateFile: (file) async {
                      final wallet = await context
                          .read<LoginBloc>()
                          .validateAndReturnWalletFile(file);

                      return wallet != null;
                    },
                    platformSupportsDragAndDrop: !AppPlatform.isMobile,
                  ),
                  const SizedBox(height: 24),
                  ArDriveOverlay(
                    visible: _showSecurityOverlay,
                    content: ArDriveCard(
                      boxShadow: BoxShadowCard.shadow100,
                      contentPadding: const EdgeInsets.all(16),
                      width: 300,
                      content: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: appLocalizationsOf(context)
                                  .securityWalletOverlay,
                              style: ArDriveTypography.body.smallBold(),
                            ),
                            TextSpan(
                              text: ' ',
                              style: ArDriveTypography.body.buttonNormalRegular(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgOnAccent,
                              ),
                            ),
                            TextSpan(
                              text: appLocalizationsOf(context).learnMore,
                              style: ArDriveTypography.body
                                  .buttonNormalRegular(
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeFgOnAccent,
                                  )
                                  .copyWith(
                                    decoration: TextDecoration.underline,
                                  ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openUrl(
                                      url: Resources.howDoesKeyFileLoginWork,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    anchor: const Aligned(
                      follower: Alignment.bottomCenter,
                      target: Alignment.topCenter,
                      offset: Offset(0, 4),
                    ),
                    onVisibleChange: (visible) {
                      setState(() {
                        _showSecurityOverlay = visible;
                      });
                    },
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _showSecurityOverlay = !_showSecurityOverlay;
                        });
                      },
                      child: HoverWidget(
                        hoverScale: 1,
                        child: Text(
                            appLocalizationsOf(context).howDoesKeyfileLoginWork,
                            style: ArDriveTypography.body.smallBold().copyWith(
                                  decoration: TextDecoration.underline,
                                  fontSize: 14,
                                  height: 1.5,
                                )),
                      ),
                    ),
                  ),
                  if (widget.isArConnectAvailable) ...[
                    const SizedBox(height: 40),
                    Row(
                      children: [
                        Expanded(
                            child: Container(
                          decoration: const ShapeDecoration(
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                width: 0.50,
                                strokeAlign: BorderSide.strokeAlignCenter,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        )),
                        Padding(
                            padding: const EdgeInsets.only(left: 25, right: 25),
                            child: Text(
                              'OR',
                              textAlign: TextAlign.center,
                              style: ArDriveTypography.body
                                  .smallBold(color: const Color(0xFF9E9E9E)),
                            )),
                        Expanded(
                            child: Container(
                          decoration: const ShapeDecoration(
                            shape: RoundedRectangleBorder(
                              side: BorderSide(
                                width: 0.50,
                                strokeAlign: BorderSide.strokeAlignCenter,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        )),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: ArDriveButton(
                              icon: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: ArDriveIcons.arconnectIcon1(
                                    color: colors.themeFgDefault,
                                  )),
                              style: ArDriveButtonStyle.secondary,
                              fontStyle: ArDriveTypography.body
                                  .smallBold700(color: colors.themeFgDefault),
                              onPressed: () {
                                context
                                    .read<LoginBloc>()
                                    .add(const AddWalletFromArConnect());
                              },
                              // TODO: create/update localization key
                              text: 'Login with ArConnect',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(
                    height: 72,
                  ),
                ],
              ),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      // TODO: create/update localization key
                      text: 'New user? Get started here!',
                      style: ArDriveTypography.body
                          .smallBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgMuted)
                          .copyWith(decoration: TextDecoration.underline),

                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          context
                              .read<LoginBloc>()
                              .add(const CreateNewWallet());
                        },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  SizedBox heightSpacing() {
    return SizedBox(
        height: MediaQuery.of(context).size.height < 700 ? 8.0 : 24.0);
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.content, this.showLattice = false});

  final Widget content;
  final bool showLattice;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      double horizontalPadding = 72;

      final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

      final deviceType = getDeviceType(MediaQuery.of(context).size);

      switch (deviceType) {
        case DeviceScreenType.desktop:
          if (constraints.maxWidth >= 512) {
            horizontalPadding = 72;
          } else {
            horizontalPadding = constraints.maxWidth * 0.15 >= 72
                ? 72
                : constraints.maxWidth * 0.15;
          }
          break;
        case DeviceScreenType.tablet:
          horizontalPadding = 32;
          break;
        case DeviceScreenType.mobile:
          horizontalPadding = 16;
          break;
        default:
          horizontalPadding = 72;
      }

      return ArDriveCard(
          backgroundColor:
              ArDriveTheme.of(context).themeData.colors.themeBgSurface,
          borderRadius: 24,
          boxShadow: BoxShadowCard.shadow80,
          contentPadding: EdgeInsets.zero,
          content: Stack(
            children: [
              if (showLattice)
                Positioned(
                  bottom: 30,
                  right: 0,
                  child: SvgPicture.asset(
                    isDarkMode
                        ? Resources.images.login.lattice
                        : Resources.images.login.latticeLight,
                    // fit: BoxFit.fitHeight,
                  ),
                ),
              Container(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  _topPadding(context),
                  horizontalPadding,
                  _bottomPadding(context),
                ),
                child: content,
              )
            ],
          )
          // content,
          );
    });
  }

  double _topPadding(BuildContext context) {
    if (MediaQuery.of(context).size.height * 0.05 > 53) {
      return 53;
    } else {
      return MediaQuery.of(context).size.height * 0.05;
    }
  }

  double _bottomPadding(BuildContext context) {
    if (MediaQuery.of(context).size.height * 0.05 > 43) {
      return 43;
    } else {
      return MediaQuery.of(context).size.height * 0.05;
    }
  }
}

class PromptPasswordView extends StatefulWidget {
  const PromptPasswordView({super.key, this.wallet});

  final Wallet? wallet;

  @override
  State<PromptPasswordView> createState() => _PromptPasswordViewState();
}

class _PromptPasswordViewState extends State<PromptPasswordView> {
  final _passwordController = TextEditingController();

  bool _isPasswordValid = false;

  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      child: _LoginCard(
        content: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                appLocalizationsOf(context).welcomeBackEmphasized,
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline.headline4Bold(),
              ),
              Column(
                children: [
                  ArDriveTextField(
                      showObfuscationToggle: true,
                      controller: _passwordController,
                      obscureText: true,
                      autofocus: true,
                      autofillHints: const [AutofillHints.password],
                      hintText: appLocalizationsOf(context).enterPassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          setState(() {
                            _isPasswordValid = false;
                          });
                          return appLocalizationsOf(context).validationRequired;
                        }

                        setState(() {
                          _isPasswordValid = true;
                        });

                        return null;
                      },
                      onFieldSubmitted: (_) async {
                        if (_isPasswordValid) {
                          _onSubmit();
                        }
                      }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ArDriveButton(
                      isDisabled: !_isPasswordValid,
                      onPressed: () {
                        _onSubmit();
                      },
                      text: appLocalizationsOf(context).proceed,
                    ),
                  ),
                  const SizedBox(height: 16),
                  BiometricToggle(
                    onEnableBiometric: () {
                      /// Biometrics was enabled
                      context
                          .read<LoginBloc>()
                          .add(const UnLockWithBiometrics());
                    },
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ArDriveButton(
                  onPressed: () {
                    _forgetWallet(context);
                  },
                  style: ArDriveButtonStyle.tertiary,
                  text: appLocalizationsOf(context).forgetWallet,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onSubmit() {
    if (widget.wallet == null) {
      context.read<LoginBloc>().add(
            UnlockUserWithPassword(
              password: _passwordController.text,
            ),
          );
    } else {
      context.read<LoginBloc>().add(
            LoginWithPassword(
              password: _passwordController.text,
              wallet: widget.wallet!,
            ),
          );
    }
  }
}

class CreatePasswordView extends StatefulWidget {
  const CreatePasswordView({super.key, required this.wallet});

  final Wallet wallet;

  @override
  State<CreatePasswordView> createState() => _CreatePasswordViewState();
}

class _CreatePasswordViewState extends State<CreatePasswordView> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<ArDriveFormState>();

  bool _isTermsChecked = false;

  bool _passwordIsValid = false;
  bool _confirmPasswordIsValid = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: _LoginCard(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => const SizedBox.shrink(),
                mobile: (context) => ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              Text(
                appLocalizationsOf(context).createAndConfirmPassword,
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline.headline5Regular(),
              ),
              const SizedBox(height: 16),
              _createPasswordForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createPasswordForm() {
    return ArDriveForm(
      key: _formKey,
      child: Column(
        children: [
          ArDriveTextField(
            autofocus: true,
            controller: _passwordController,
            showObfuscationToggle: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            hintText: appLocalizationsOf(context).enterPassword,
            onChanged: (s) {
              _formKey.currentState?.validate();
            },
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.isEmpty) {
                setState(() {
                  _passwordIsValid = false;
                });
                return appLocalizationsOf(context).validationRequired;
              }

              setState(() {
                _passwordIsValid = true;
              });

              return null;
            },
          ),
          const SizedBox(height: 16),
          ArDriveTextField(
            controller: _confirmPasswordController,
            showObfuscationToggle: true,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            hintText: appLocalizationsOf(context).confirmPassword,
            textInputAction: TextInputAction.done,
            validator: (value) {
              if (value == null || value.isEmpty) {
                setState(() {
                  _confirmPasswordIsValid = false;
                });
                return appLocalizationsOf(context).validationRequired;
              } else if (value != _passwordController.text) {
                setState(() {
                  _confirmPasswordIsValid = false;
                });
                return appLocalizationsOf(context).passwordMismatch;
              }
              setState(() {
                _confirmPasswordIsValid = true;
              });

              return null;
            },
            onFieldSubmitted: (_) {
              if (_passwordIsValid &&
                  _confirmPasswordIsValid &&
                  _isTermsChecked) {
                _onSubmit();
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ArDriveCheckBox(
                title: '',
                checked: _isTermsChecked,
                onChange: ((value) {
                  setState(() => _isTermsChecked = value);
                }),
              ),
              Flexible(
                child: GestureDetector(
                  onTap: () => openUrl(
                    url: Resources.agreementLink,
                  ),
                  child: ArDriveClickArea(
                    child: Text.rich(
                      TextSpan(
                        children:
                            splitTranslationsWithMultipleStyles<InlineSpan>(
                          originalText:
                              appLocalizationsOf(context).aggreeToTerms_body,
                          defaultMapper: (text) => TextSpan(text: text),
                          parts: {
                            appLocalizationsOf(context).aggreeToTerms_link:
                                (text) => TextSpan(
                                      text: text,
                                      style: const TextStyle(
                                        decoration: TextDecoration.underline,
                                      ),
                                    ),
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              isDisabled: !_isTermsChecked ||
                  _passwordIsValid == false ||
                  _confirmPasswordIsValid == false,
              onPressed: _onSubmit,
              text: appLocalizationsOf(context).proceed,
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ArDriveButton(
              onPressed: () {
                _forgetWallet(context);
              },
              style: ArDriveButtonStyle.tertiary,
              text: appLocalizationsOf(context).forgetWallet,
            ),
          ),
        ],
      ),
    );
  }

  void _onSubmit() {
    final isValid = _formKey.currentState!.validateSync();

    if (!isValid) {
      showAnimatedDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.triangle(
              size: 88,
              color: ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
            ),
            title: appLocalizationsOf(context).passwordCannotBeEmpty,
            content: appLocalizationsOf(context).pleaseTryAgain,
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              )
            ],
          ));
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      showAnimatedDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.triangle(
              size: 88,
              color: ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
            ),
            title: appLocalizationsOf(context).passwordDoNotMatch,
            content: appLocalizationsOf(context).pleaseTryAgain,
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              )
            ],
          ));
      return;
    }

    context.read<LoginBloc>().add(
          CreatePassword(
            password: _passwordController.text,
            wallet: widget.wallet,
          ),
        );
  }
}

class OnBoardingView extends StatefulWidget {
  const OnBoardingView({
    super.key,
    required this.wallet,
  });
  final Wallet wallet;

  @override
  State<OnBoardingView> createState() => OnBoardingViewState();
}

class OnBoardingViewState extends State<OnBoardingView> {
  int _currentPage = 0;

  List<_OnBoarding> get _list => [
        _OnBoarding(
          primaryButtonText: appLocalizationsOf(context).next,
          primaryButtonAction: () {
            setState(() {
              _currentPage++;
            });
          },
          secundaryButtonHasIcon: false,
          secundaryButtonText: appLocalizationsOf(context).skip,
          secundaryButtonAction: () {
            context.read<LoginBloc>().add(
                  FinishOnboarding(
                    wallet: widget.wallet,
                  ),
                );
          },
          title: appLocalizationsOf(context).onboarding1Title,
          description: appLocalizationsOf(context).onboarding1Description,
          illustration: AssetImage(Resources.images.login.gridImage),
        ),
        _OnBoarding(
          primaryButtonText: appLocalizationsOf(context).next,
          primaryButtonAction: () {
            setState(() {
              _currentPage++;
            });
          },
          secundaryButtonText: appLocalizationsOf(context).backButtonOnboarding,
          secundaryButtonAction: () {
            setState(() {
              _currentPage--;
            });
          },
          title: appLocalizationsOf(context).onboarding2Title,
          description: appLocalizationsOf(context).onboarding2Description,
          illustration: AssetImage(Resources.images.login.gridImage),
        ),
        _OnBoarding(
          primaryButtonText: appLocalizationsOf(context).diveInButtonOnboarding,
          primaryButtonAction: () {
            context.read<LoginBloc>().add(
                  FinishOnboarding(
                    wallet: widget.wallet,
                  ),
                );
          },
          secundaryButtonText: appLocalizationsOf(context).backButtonOnboarding,
          secundaryButtonAction: () {
            setState(() {
              _currentPage--;
            });
          },
          title: appLocalizationsOf(context).onboarding3Title,
          description: appLocalizationsOf(context).onboarding3Description,
          illustration: AssetImage(Resources.images.login.gridImage),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout.builder(
      desktop: (context) => Material(
        color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
                child: Align(
                  child: MaxDeviceSizesConstrainedBox(
                    child: _FadeThroughTransitionSwitcher(
                      fillColor: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeBgSurface,
                      child: _buildOnBoardingContent(),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FractionallySizedBox(
                heightFactor: 1,
                child: _buildOnBoardingIllustration(_currentPage),
              ),
            ),
          ],
        ),
      ),
      mobile: (context) => Scaffold(
        resizeToAvoidBottomInset: true,
        body: Container(
          color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
          child: Align(
            child: MaxDeviceSizesConstrainedBox(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: _buildOnBoardingContent(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOnBoardingIllustration(int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: 0.25,
          child: ArDriveImage(
            image: _list[_currentPage].illustration,
            fit: BoxFit.cover,
            height: double.maxFinite,
            width: double.maxFinite,
          ),
        ),
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ArDriveImage(
                image: AssetImage(
                  Resources.images.login.ardriveLogoOnboarding,
                ),
                fit: BoxFit.contain,
                height: 240,
                width: 240,
              ),
              const SizedBox(
                height: 48,
              ),
              Align(
                alignment: Alignment.topCenter,
                child: ArDrivePaginationDots(
                  currentPage: _currentPage,
                  numberOfPages: _list.length,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOnBoardingContent() {
    return _OnBoardingContent(
      key: ValueKey(_currentPage),
      onBoarding: _list[_currentPage],
    );
  }
}

class _OnBoardingContent extends StatelessWidget {
  const _OnBoardingContent({
    super.key,
    required this.onBoarding,
  });

  final _OnBoarding onBoarding;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        Text(
          onBoarding.title,
          style: ArDriveTypography.headline.headline3Bold(),
        ),
        Text(
          onBoarding.description,
          style: ArDriveTypography.body.buttonXLargeBold(),
        ),
        Row(
          key: const ValueKey('buttons'),
          children: [
            ArDriveButton(
              icon: onBoarding.secundaryButtonHasIcon
                  ? ArDriveIcons.arrowLeftOutline()
                  : null,
              style: ArDriveButtonStyle.secondary,
              text: onBoarding.secundaryButtonText,
              onPressed: () => onBoarding.secundaryButtonAction(),
            ),
            const SizedBox(width: 32),
            ArDriveButton(
              iconAlignment: IconButtonAlignment.right,
              icon: ArDriveIcons.arrowRightOutline(
                color: Colors.white,
              ),
              text: onBoarding.primaryButtonText,
              onPressed: () => onBoarding.primaryButtonAction(),
            ),
          ],
        ),
      ],
    );
  }
}

class _OnBoarding {
  final String title;
  final String description;
  final String primaryButtonText;
  final String secundaryButtonText;
  final Function primaryButtonAction;
  final Function secundaryButtonAction;
  final bool secundaryButtonHasIcon;
  final ImageProvider illustration;

  _OnBoarding({
    required this.title,
    required this.description,
    required this.primaryButtonText,
    required this.secundaryButtonText,
    required this.illustration,
    required this.primaryButtonAction,
    required this.secundaryButtonAction,
    this.secundaryButtonHasIcon = true,
  });
}

class _FadeThroughTransitionSwitcher extends StatelessWidget {
  const _FadeThroughTransitionSwitcher({
    required this.fillColor,
    required this.child,
    Key? key,
  }) : super(key: key);

  final Widget child;
  final Color fillColor;

  @override
  Widget build(BuildContext context) {
    return PageTransitionSwitcher(
      transitionBuilder: (child, animation, secondaryAnimation) {
        return FadeThroughTransition(
          fillColor: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      },
      child: child,
    );
  }
}

void _forgetWallet(
  BuildContext context,
) {
  final actions = [
    ModalAction(
      action: () {
        Navigator.pop(context);
      },
      title: appLocalizationsOf(context).cancel,
    ),
    ModalAction(
      action: () {
        Navigator.pop(context);

        context.read<LoginBloc>().add(const ForgetWallet());
      },
      title: appLocalizationsOf(context).ok,
    )
  ];
  showStandardDialog(
    context,
    title: appLocalizationsOf(context).forgetWalletTitle,
    description: appLocalizationsOf(context).forgetWalletDescription,
    actions: actions,
  );
}

class MaxDeviceSizesConstrainedBox extends StatelessWidget {
  final double maxHeightPercent;
  final double defaultMaxHeight;
  final double defaultMaxWidth;
  final Widget child;

  const MaxDeviceSizesConstrainedBox({
    Key? key,
    this.maxHeightPercent = 0.8,
    this.defaultMaxWidth = _defaultLoginCardMaxWidth,
    this.defaultMaxHeight = _defaultLoginCardMaxHeight,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * maxHeightPercent;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: defaultMaxWidth,
        maxHeight: defaultMaxHeight > maxHeight ? maxHeight : defaultMaxHeight,
      ),
      child: child,
    );
  }
}

const double _defaultLoginCardMaxWidth = 512;
const double _defaultLoginCardMaxHeight = 489;

class EnterSeedPhraseView extends StatefulWidget {
  const EnterSeedPhraseView({super.key});

  // final Wallet wallet;

  @override
  State<EnterSeedPhraseView> createState() => _EnterSeedPhraseViewState();
}

class _EnterSeedPhraseViewState extends State<EnterSeedPhraseView> {
  final _seedPhraseController = ArDriveMultlineObscureTextController();
  final _formKey = GlobalKey<ArDriveFormState>();
  // var _seedPhraseFormatIsValid = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: _LoginCard(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => const SizedBox.shrink(),
                mobile: (context) => ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  // TODO: create/update localization key
                  'Enter Seed Phrase',
                  style: ArDriveTypography.headline.headline4Regular(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                // TODO: create/update localization key
                'Please enter your 12 word seed phrase and separate each word with a space.',
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.smallBold(),
              ),
              const SizedBox(height: 50),
              _createSeedPhraseForm(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createSeedPhraseForm() {
    return ArDriveForm(
      key: _formKey,
      child: Column(
        children: [
          Align(
              alignment: Alignment.topLeft,
              child: Text(
                // TODO: create/update localization key
                'Seed Phrase',
                style:
                    ArDriveTypography.body.smallBold().copyWith(fontSize: 14),
              )),
          const SizedBox(height: 8),
          ArDriveTextField(
            autofocus: true,
            controller: _seedPhraseController,
            showObfuscationToggle: true,
            obscureText: true,
            // TODO: create/update localization key
            hintText: 'Enter Seed Phrase',
            textInputAction: TextInputAction.next,
            minLines: 3,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              onPressed: _onSubmit,
              // TODO: create/update localization key
              text: 'Continue',
              fontStyle:
                  ArDriveTypography.body.smallBold700(color: Colors.white),
            ),
          ),
          const SizedBox(height: 56),
          Align(
              alignment: Alignment.bottomLeft,
              child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      context.read<LoginBloc>().add(const ForgetWallet());
                    },
                    child: Row(children: [
                      ArDriveIcons.carretLeft(
                          size: 16,
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgDefault),
                      Text(appLocalizationsOf(context).back),
                    ]),
                  ))),
        ],
      ),
    );
  }

  void _onSubmit() async {
    final isValid = _seedPhraseController.text.isNotEmpty &&
        bip39.validateMnemonic(_seedPhraseController.text);

    if (!isValid) {
      showAnimatedDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.triangle(
              size: 88,
              color: ArDriveTheme.of(context).themeData.colors.themeErrorMuted,
            ),
            title: appLocalizationsOf(context).error,
            // TODO: create/update localization key
            content:
                'The seed phrase you have provided is invalid. Please correct and retry.',
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: appLocalizationsOf(context).ok,
              )
            ],
          ));
      return;
    }

    context
        .read<LoginBloc>()
        .add(AddWalletFromMnemonic(_seedPhraseController.text));
  }
}

class GenerateWalletView extends StatefulWidget {
  const GenerateWalletView({super.key});

  @override
  State<GenerateWalletView> createState() => _GenerateWalletViewState();
}

class _GenerateWalletViewState extends State<GenerateWalletView> {
  late Timer _periodicTimer;
  int _index = 0;

  // TODO: create/update localization keys
  final _messages = [
    'ArDrive helps you upload your data to the permaweb and keep it safe for generations to come!',
    'With Turbo you can pay with a credit card and increase the reliability of your uploads!',
    'You can download a copy of your keyfile from the Profile menu.',
    'If you have large drives, you can take a Snapshot to speed up the syncing time.'
  ];
  late String _message;

  @override
  void initState() {
    super.initState();

    // TODO: create/update localization key
    _message = 'Did you know?\n\n${_messages[0]}';

    _periodicTimer = Timer.periodic(const Duration(seconds: 7), (Timer t) {
      setState(() {
        _index = (_index + 1) % _messages.length;
        // TODO: create/update localization key
        _message = 'Did you know?\n\n${_messages[_index]}';
      });
    });
  }

  @override
  void dispose() {
    _periodicTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var colors = ArDriveTheme.of(context).themeData.colors;

    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: SingleChildScrollView(
        child: _LoginCard(
          showLattice: true,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                // TODO: create/update localization key
                'Generating Wallet...',
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline
                    .headline4Regular(color: colors.themeFgDefault)
                    .copyWith(fontSize: 32),
              ),
              const SizedBox(height: 74),
              // Did you Know box
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.only(right: 16),
                    width: 227,
                    height: 150,
                    child: Text(
                      _message,
                      textAlign: TextAlign.right,
                      style: ArDriveTypography.body
                          .smallBold700(color: colors.themeFgMuted),
                    ),
                  ),
                  Container(
                      margin: const EdgeInsets.fromLTRB(239, 5, 0, 0),
                      width: 5,
                      height: 20,
                      child: CustomPaint(
                        painter: AccentPainter(lineHeight: 173),
                      )),
                ],
              ),
              const SizedBox(height: 79),
              // Info Box
              Container(
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: colors.themeBorderDefault, width: 1),
                      color: colors.themeBgSurface,
                      borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ArDriveIcons.info(size: 24, color: colors.themeFgSubtle),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                            // TODO: create/update localization key
                            'Nobody (including the ArDrive core team) can help you recover your wallet if the keyfile is lost. So, remember to keep it safe!',
                            style: ArDriveTypography.body
                                .buttonNormalBold(color: colors.themeFgSubtle)),
                      ),
                    ],
                  ))
            ],
          ),
        ),
      ),
    );
  }
}

class DownloadWalletView extends StatefulWidget {
  const DownloadWalletView(
      {super.key, required this.mnemonic, required this.wallet});

  final String mnemonic;
  final Wallet wallet;

  @override
  State<DownloadWalletView> createState() => _DownloadWalletViewState();
}

class _DownloadWalletViewState extends State<DownloadWalletView> {
  @override
  Widget build(BuildContext context) {
    return MaxDeviceSizesConstrainedBox(
      defaultMaxHeight: 798,
      maxHeightPercent: 1,
      child: _LoginCard(
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ScreenTypeLayout.builder(
                desktop: (context) => const SizedBox.shrink(),
                mobile: (context) => ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              ArDriveIcons.checkmark(
                  size: 32,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault),
              const SizedBox(height: 16),
              Text(
                // TODO: create/update localization key
                'Wallet Created',
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline
                    .headline4Regular(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgDefault)
                    .copyWith(fontSize: 32),
              ),
              const SizedBox(height: 8),
              Text(
                // TODO: create/update localization key
                'Download your keyfile. You can also find it under the profile menu.',
                textAlign: TextAlign.center,
                style: ArDriveTypography.body.smallBold(
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgSubtle),
              ),
              const SizedBox(height: 56),
              MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                    onTap: () {
                      _onDownload();
                    },
                    child: Container(
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeBorderDefault,
                              width: 1),
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeBgSurface),
                      padding: const EdgeInsets.all(6),
                      child: Container(
                          width: double.maxFinite,
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(3),
                              // border: Border.all(color: ArDriveTheme.of(context).themeData.colors.themeBorderDefault, width: 1),
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeBgSubtle),
                          padding: const EdgeInsets.all(44),
                          child: Column(
                            children: [
                              ArDriveIcons.download(size: 40),
                              const SizedBox(height: 4),
                              // TODO: create/update localization key
                              Text('Download Keyfile',
                                  style: ArDriveTypography.body.smallBold700(
                                      color: ArDriveTheme.of(context)
                                          .themeData
                                          .colors
                                          .themeFgDefault))
                            ],
                          )),
                    )),
              ),
              const SizedBox(height: 56),
              SizedBox(
                width: double.infinity,
                child: ArDriveButton(
                  onPressed: () {
                    context
                        .read<LoginBloc>()
                        .add(CompleteWalletGeneration(widget.wallet));
                  },
                  // TODO: create/update localization key
                  text: 'Continue',
                  fontStyle:
                      ArDriveTypography.body.smallBold700(color: Colors.white),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }

  void _onDownload() async {
    final jsonTxt = jsonEncode(widget.wallet.toJwk());

    final ArDriveIO io = ArDriveIO();
    final bytes = Uint8List.fromList(utf8.encode(jsonTxt));

    await io.saveFile(await IOFile.fromData(bytes,
        name: 'ardrive-wallet.json', lastModifiedDate: DateTime.now()));
  }
}

class AccentPainter extends CustomPainter {
  double lineHeight;

  AccentPainter({required this.lineHeight});

  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.red.shade500
      ..style = PaintingStyle.fill;
    canvas.drawCircle(const Offset(3, 8), 2.5, paint);
    var rect = Rect.fromLTWH(2.5, 8, 1, lineHeight);
    paint = Paint()
      ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.red.shade500,
            Colors.red.shade500,
            Colors.red.shade500.withAlpha(0)
          ]).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

class CreateNewWalletView extends StatefulWidget {
  const CreateNewWalletView({super.key, required this.mnemonic});

  final String mnemonic;

  @override
  State<CreateNewWalletView> createState() => CreateNewWalletViewState();
}

class WordOption {
  WordOption(this.word, this.index);

  int index;
  String word;
}

class CreateNewWalletViewState extends State<CreateNewWalletView> {
  int _currentPage = 0;
  bool _isBlurredSeedPhrase = true;
  late final List<String> _mnemonicWords;

  final Completer<Wallet> preGeneratedWallet = Completer();

  List<WordOption> _wordsToCheck = [];
  List<WordOption> _wordOptions = [];
  bool _wordsAreCorrect = false;

  @override
  void initState() {
    super.initState();
    _mnemonicWords = widget.mnemonic.split(' ');
    _resetMemoryCheckItems();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      var wallet = await generateWalletFromMnemonic(widget.mnemonic);
      preGeneratedWallet.complete(wallet);
    });
  }

  void advancePage() async {
    if (_currentPage == 2) {
      context
          .read<LoginBloc>()
          .add(AddWalletFromCompleter(widget.mnemonic, preGeneratedWallet));
    } else {
      setState(() {
        _isBlurredSeedPhrase = true;
        _wordsAreCorrect = false;
        _currentPage++;
      });
    }
  }

  void back() {
    _isBlurredSeedPhrase = true;
    _wordsAreCorrect = false;
    if (_currentPage == 0) {
      // Navigator.pop(context);
      context.read<LoginBloc>().add(const ForgetWallet());
    } else {
      setState(() {
        _currentPage--;
      });
    }
  }

  void _resetMemoryCheckItems() {
    final indices = List<int>.generate(_mnemonicWords.length, (i) => i);
    indices.shuffle();

    _wordsToCheck = indices
        .sublist(0, 4)
        .map(
          (e) => WordOption('', e),
        )
        .toList();

    _wordOptions = _wordsToCheck
        .map((e) => WordOption(_mnemonicWords[e.index], -1))
        .toList();

    var wordSet = _wordOptions.map((e) => e.word).toSet();

    var optionsIndex = 4;
    while (optionsIndex < 8) {
      for (var randWord in bip39.generateMnemonic().split(' ')) {
        if (!wordSet.contains(randWord)) {
          _wordOptions.add(WordOption(randWord, -1));
          wordSet.add(randWord);
          optionsIndex++;
          if (optionsIndex >= 8) {
            break;
          }
        }
      }
    }

    _wordOptions.shuffle();
  }

  List<Widget> createRows(
      {required List<Widget> items,
      required int rowCount,
      required double hGap,
      required double vGap}) {
    List<Widget> rows = [];

    int count = 0;

    while (count < items.length) {
      List<Widget> rowItems = [];
      for (int i = 0; i < rowCount; i++) {
        if (count < items.length) {
          if (i % rowCount != 0) {
            rowItems.add(SizedBox(width: hGap));
          }
          rowItems.add(items[count]);
          count++;
        }
      }
      if (count > rowCount) {
        rows.add(SizedBox(height: vGap));
      }
      rows.add(Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: rowItems,
      ));
    }
    return rows;
  }

  Widget _buildContent(BuildContext context) {
    Widget view;

    switch (_currentPage) {
      case 2:
        view = _buildConfirmYourSeedPhrase();
        break;
      case 1:
        view = _buildWriteDownSeedPhrase();
        break;
      default:
        view = _buildGettingStarted();
    }

    return view;
  }

  Widget _backButton() {
    var colors = ArDriveTheme.of(context).themeData.colors;
    return Expanded(
        child: Container(
            decoration: BoxDecoration(
                border: Border(
                    top: BorderSide(
                        color: colors.themeBorderDefault, width: 1))),
            child: TextButton(
              style: ButtonStyle(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                    (Set<MaterialState> states) {
                  return colors.themeFgDefault.withOpacity(0.1);
                }),
              ),
              onPressed: back,
              child: Center(
                  // TODO: create/update localization key
                  child: Text('Back',
                      style: ArDriveTypography.body
                          .smallBold700(color: colors.themeFgDefault))),
            )));
  }

  Widget _nextButton({required String text, required bool isDisabled}) {
    return Expanded(
        child: ArDriveButton(
            isDisabled: isDisabled,
            iconAlignment: IconButtonAlignment.right,
            icon: Container(
                padding: const EdgeInsets.only(top: 4),
                child: Icon(Icons.arrow_forward,
                    color: ArDriveTheme.of(context)
                        .themeData
                        .colors
                        .themeFgOnAccent,
                    size: 20)),
            fontStyle: ArDriveTypography.body.smallBold700(
                color:
                    ArDriveTheme.of(context).themeData.colors.themeFgOnAccent),
            maxWidth: double.maxFinite,
            borderRadius: 0,
            text: text,
            onPressed: advancePage));
  }

  Widget _buildCard(List<String> cardInfo) {
    final screenSize = MediaQuery.of(context).size;

    final wideScreen = screenSize.width > (374 * 2 + 24 * 3);
    final containerWidth = wideScreen ? 374.0 : screenSize.width - 40.0;
    final height = wideScreen ? 180.0 : null;

    return Stack(
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              padding: const EdgeInsets.only(left: 35),
              child: Text(
                cardInfo[0],
                style: ArDriveTypography.headline.headline5Regular(),
              )),
          const SizedBox(height: 16),
          Container(
            width: containerWidth,
            height: height,
            padding: const EdgeInsets.fromLTRB(30, 24, 30, 24),
            decoration: BoxDecoration(
              color: ArDriveTheme.of(context).themeData.colors.themeBgSurface,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              cardInfo[1],
              style: ArDriveTypography.body
                  .bodyRegular()
                  .copyWith(fontSize: 16, height: 1.4),
            ),
          )
        ]),
        Container(
          margin: const EdgeInsets.fromLTRB(15, 5, 0, 0),
          width: 5,
          height: 20,
          child: CustomPaint(
            painter: AccentPainter(lineHeight: 83),
          ),
        ),
      ],
    );
  }

  Widget blurred(double width, String word, bool isBlurred) {
    var radius = const Radius.circular(4);

    final colors = ArDriveTheme.of(context).themeData.colors;
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    var text = Container(
        width: width,
        height: 45,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
            color: isDarkMode ? colors.themeBgSurface : colors.themeBgSubtle,
            borderRadius:
                BorderRadius.only(topRight: radius, bottomRight: radius)),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: Text(word,
            style:
                ArDriveTypography.body.smallBold(color: colors.themeFgMuted)));

    return isBlurred
        ? ClipRect(
            child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: text,
          ))
        : text;
  }

  Widget _buildSeedPhraseWord(int num, String word) {
    final screenSize = MediaQuery.of(context).size;
    final width = screenSize.width > (176 * 3 + 24 * 4)
        ? 176.0
        : (screenSize.width - 24 * 3) / 2;
    var radius = const Radius.circular(4);
    var colors = ArDriveTheme.of(context).themeData.colors;
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    return SizedBox(
        width: width,
        height: 45,
        child: Row(
          children: [
            Container(
                width: 22,
                height: 45,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color:
                        isDarkMode ? colors.themeBgCanvas : colors.themeGbMuted,
                    borderRadius:
                        BorderRadius.only(topLeft: radius, bottomLeft: radius)),
                child: Center(
                    child: Text(
                  '$num',
                  style: ArDriveTypography.body
                      .smallBold700(color: colors.themeFgDefault),
                ))),
            blurred(width - 22, word, _isBlurredSeedPhrase),
          ],
        ));
  }

  Widget _buildWordToCheck(double width, WordOption wordOption) {
    var radius = const Radius.circular(2);
    var colors = ArDriveTheme.of(context).themeData.colors;

    var currentWordToCheckIndex =
        _wordsToCheck.indexWhere((e) => e.word.isEmpty);
    var showCursor = (currentWordToCheckIndex >= 0 &&
        wordOption == _wordsToCheck[currentWordToCheckIndex]);

    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    var borderColor = showCursor
        ? colors.themeFgDefault
        : isDarkMode
            ? colors.themeBgCanvas
            : colors.themeBgSubtle;
    var numberColor =
        showCursor ? colors.themeBgSurface : colors.themeFgDefault;

    return Container(
        width: width,
        height: 45,
        decoration: BoxDecoration(
            color: borderColor, borderRadius: BorderRadius.circular(4)),
        child: Row(
          children: [
            Container(
                width: 22,
                height: 45,
                alignment: Alignment.center,
                child: Center(
                    child: Text('${wordOption.index + 1}',
                        style: ArDriveTypography.body
                            .smallBold700(color: numberColor)))),
            Stack(
                alignment:
                    showCursor ? Alignment.centerLeft : Alignment.centerRight,
                children: [
                  Container(
                      width: width - 23,
                      height: 43,
                      decoration: BoxDecoration(
                          color: colors.themeBgSurface,
                          borderRadius: BorderRadius.only(
                              topRight: radius, bottomRight: radius)),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(wordOption.word,
                          style: ArDriveTypography.body
                              .smallBold700(color: colors.themeFgDefault))),
                  if (wordOption.word.isNotEmpty)
                    IconButton.filled(
                        onPressed: () {
                          setState(() {
                            for (var element in _wordOptions) {
                              if (element.word == wordOption.word) {
                                element.index = -1;
                              }
                            }
                            wordOption.word = '';
                          });
                        },
                        icon: Icon(
                          Icons.highlight_off,
                          size: 16,
                          color: colors.themeFgDefault,
                        )),
                ])
          ],
        ));
  }

  Widget _buildConfirmSeedPhraseWordOption(
      double width, WordOption wordOption) {
    var radius = const Radius.circular(4);
    var selected = wordOption.index >= 0;
    var colors = ArDriveTheme.of(context).themeData.colors;
    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    var currentWordToCheckIndex =
        _wordsToCheck.indexWhere((e) => e.word.isEmpty);

    return selected
        ? SizedBox(
            width: width,
            height: 45,
            child: Row(
              children: [
                Container(
                    width: 22,
                    height: 45,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: colors.themeAccentBrand,
                        borderRadius: BorderRadius.only(
                            topLeft: radius, bottomLeft: radius)),
                    child: Center(
                        child: Text('${wordOption.index + 1}',
                            style: ArDriveTypography.body
                                .smallBold700(color: colors.themeFgOnAccent)))),
                Container(
                    width: width - 22,
                    height: 45,
                    decoration: BoxDecoration(
                        color: colors.themeFgDefault,
                        borderRadius: BorderRadius.only(
                            topRight: radius, bottomRight: radius)),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(wordOption.word,
                        style: ArDriveTypography.body
                            .smallBold700(color: colors.themeBgSurface)))
              ],
            ))
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
                onTap: () {
                  if (currentWordToCheckIndex == 3) {
                    var wordToCheck = _wordsToCheck[currentWordToCheckIndex];
                    wordToCheck.word = wordOption.word;
                    wordOption.index = wordToCheck.index;

                    if (_wordsToCheck.every((element) =>
                        _mnemonicWords[element.index] == element.word)) {
                      setState(() {
                        _wordsAreCorrect = true;
                      });
                    } else {
                      setState(() {
                        _resetMemoryCheckItems();
                        var snackBar = SnackBar(
                          width: 380,
                          content: Row(children: [
                            MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    ScaffoldMessenger.of(context)
                                        .hideCurrentSnackBar();
                                  },
                                  child: Icon(Icons.close,
                                      size: 20, color: colors.themeErrorMuted),
                                )),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(
                                    // TODO: create/update localization key
                                    'Order of phrases is not correct. Please try again.',
                                    style: ArDriveTypography.body
                                        .smallBold(
                                          color: colors.themeErrorMuted,
                                        )
                                        .copyWith(fontSize: 14)))
                          ]),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                                color: colors.themeErrorMuted, width: 1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          showCloseIcon: false,
                          backgroundColor: colors.themeErrorSubtle,
                          closeIconColor: colors.themeErrorMuted,
                          behavior: SnackBarBehavior.floating,
                        );

                        ScaffoldMessenger.of(context).showSnackBar(snackBar);
                      });
                    }
                  } else {
                    setState(() {
                      var wordToCheck = _wordsToCheck[currentWordToCheckIndex];
                      wordToCheck.word = wordOption.word;
                      wordOption.index = wordToCheck.index;
                    });
                  }
                },
                child: Container(
                    width: width,
                    height: 45,
                    padding: const EdgeInsets.only(left: 16),
                    decoration: BoxDecoration(
                        color: isDarkMode
                            ? colors.themeBgSurface
                            : colors.themeBgSubtle,
                        borderRadius: BorderRadius.circular(4)),
                    alignment: Alignment.centerLeft,
                    child: Text(wordOption.word,
                        style: ArDriveTypography.body
                            .smallBold700(color: colors.themeFgDefault)))));
  }

  Widget _buildWriteDownSeedPhrase() {
    final screenSize = MediaQuery.of(context).size;

    final rowCount = screenSize.width > (176 * 3 + 24 * 4) ? 3 : 2;
    final topBottomPadding = rowCount == 2 ? 40.0 : 0.0;

    var rows = Column(
        children: createRows(
            items: _mnemonicWords
                .asMap()
                .map((i, e) => MapEntry(i, _buildSeedPhraseWord(i + 1, e)))
                .values
                .toList(),
            rowCount: rowCount,
            hGap: 24,
            vGap: 24));

    return Scaffold(
      body: Center(
          child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  top: topBottomPadding, bottom: topBottomPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    // TODO: create/update localization key
                    'Write Down Seed Phrase',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.headline
                        .headline4Regular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault)
                        .copyWith(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Container(
                      constraints: const BoxConstraints(maxWidth: 508),
                      child: Text(
                        // TODO: create/update localization key
                        'Please carefully write down your seed phrase, in this order, and keep it somewhere safe.',
                        textAlign: TextAlign.center,
                        style: ArDriveTypography.body.smallBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgSubtle),
                      )),
                  const SizedBox(height: 72),
                  rows,
                  const SizedBox(height: 72),
                  ...createRows(
                    items: [
                      TextButton.icon(
                        icon: _isBlurredSeedPhrase
                            ? ArDriveIcons.eyeClosed(
                                size: 24,
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgMuted)
                            : ArDriveIcons.eyeOpen(
                                size: 24,
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgMuted),
                        label: SizedBox(
                            width: 92,
                            child: Text(
                              // TODO: create/update localization keys
                              _isBlurredSeedPhrase
                                  ? 'Show Words'
                                  : 'Hide Words',
                              style: ArDriveTypography.body.smallBold(
                                  color: ArDriveTheme.of(context)
                                      .themeData
                                      .colors
                                      .themeFgMuted),
                            )),
                        onPressed: () {
                          setState(() {
                            _isBlurredSeedPhrase = !_isBlurredSeedPhrase;
                          });
                        },
                      ),
                      LoginCopyButton(text: widget.mnemonic),
                    ],
                    rowCount: rowCount == 3 ? 2 : 1,
                    hGap: 16,
                    vGap: 16,
                  ),
                ],
              ))),
      bottomNavigationBar: IntrinsicHeight(
          child: Row(children: [
        _backButton(),
        // TODO: create/update localization key
        _nextButton(text: 'I wrote it down', isDisabled: false)
      ])),
    );
  }

  Widget _buildConfirmYourSeedPhrase() {
    final screenSize = MediaQuery.of(context).size;

    final rowCount = screenSize.width > (176 * 4 + 24 * 5) ? 4 : 2;
    final width = rowCount == 4 ? 176.0 : (screenSize.width - 24 * 3) / 2;

    final topBottomPadding = rowCount == 2 ? 40.0 : 0.0;

    var wordsToCheck = createRows(
        items: _wordsToCheck.map((e) => _buildWordToCheck(width, e)).toList(),
        rowCount: rowCount,
        hGap: 24,
        vGap: 24);

    var wordOptions = createRows(
        items: _wordOptions.map((e) {
          return _buildConfirmSeedPhraseWordOption(width, e);
        }).toList(),
        rowCount: rowCount,
        hGap: 24,
        vGap: 24);

    return Scaffold(
      body: Center(
          child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  top: topBottomPadding, bottom: topBottomPadding),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    // TODO: create/update localization key
                    'Confirm Your Seed Phrase',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.headline
                        .headline4Regular(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgDefault)
                        .copyWith(fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // TODO: create/update localization key
                    'Please select each phrase in order to make sure it’s correct.',
                    textAlign: TextAlign.center,
                    style: ArDriveTypography.body.smallBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgSubtle),
                  ),
                  const SizedBox(height: 72),
                  ...wordsToCheck,
                  const SizedBox(height: 72),
                  ...wordOptions,
                ],
              ))),
      bottomNavigationBar: IntrinsicHeight(
          child: Row(children: [
        _backButton(),

        // TODO: create/update localization key
        _nextButton(text: 'Continue', isDisabled: !_wordsAreCorrect)
      ])),
    );
  }

  Widget _buildGettingStarted() {
    // TODO: create/update localization keys
    var cardInfos = [
      [
        'Keyfile',
        'A keyfile is another way to access your wallet. It contains encrypted information that helps us authenticate your identity. Keep it secure alongside your seed phrase.'
      ],
      [
        'Seed Phrase',
        "A seed phrase is a unique set of words that acts as the master key to your wallet. It's important because it allows us to generate your wallet from the phrase whenever you log in, which may take a moment to complete."
      ],
      [
        'Security',
        "It's crucial to safeguard both your seed phrase and keyfile. We don't retain a copy of your wallet, so losing or forgetting them may result in permanent loss of access to your funds."
      ],
      [
        'Extra Security',
        'For enhanced protection, consider storing your seed phrase in a password manager or a secure offline location. This will help prevent unauthorized access to your wallet.'
      ],
    ];

    final screenSize = MediaQuery.of(context).size;

    final rowCount = screenSize.width > (374 * 2 + 24 * 3) ? 2 : 1;
    final topBottomPadding = rowCount == 1 ? 40.0 : 0.0;

    final isDarkMode = ArDriveTheme.of(context).themeData.name == 'dark';

    return Scaffold(
      body: Stack(children: [
        Positioned(
          bottom: 0,
          right: 0,
          child: SvgPicture.asset(
            isDarkMode
                ? Resources.images.login.latticeLarge
                : Resources.images.login.latticeLargeLight,
            // fit: BoxFit.fitHeight,
          ),
        ),
        Center(
            child: SingleChildScrollView(
                padding: EdgeInsets.only(
                    top: topBottomPadding, bottom: topBottomPadding),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      // TODO: create/update localization key
                      'Getting Started',
                      textAlign: TextAlign.center,
                      style: ArDriveTypography.headline
                          .headline4Regular(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgDefault)
                          .copyWith(fontSize: 32),
                    ),
                    const SizedBox(height: 8),
                    Container(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Text(
                          // TODO: create/update localization key
                          'Learn some important information about your wallet while we begin generating it.',
                          textAlign: TextAlign.center,
                          style: ArDriveTypography.body.smallBold(
                              color: ArDriveTheme.of(context)
                                  .themeData
                                  .colors
                                  .themeFgSubtle),
                        )),
                    const SizedBox(height: 72),
                    ...createRows(
                        items: cardInfos.map(_buildCard).toList(),
                        rowCount: rowCount,
                        hGap: 24,
                        vGap: 40)
                  ],
                )))
      ]),
      bottomNavigationBar: IntrinsicHeight(
          child: Row(children: [
        _backButton(),
        // TODO: create/update localization key
        _nextButton(text: 'Continue', isDisabled: false)
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
        color: ArDriveTheme.of(context).themeData.colors.themeBgCanvas,
        child: _buildContent(context));
  }
}

class LoginCopyButton extends StatefulWidget {
  final String text;
  final double size;
  final bool showCopyText;
  final Widget? child;
  final int positionY;
  final int positionX;
  final Color? copyMessageColor;

  const LoginCopyButton({
    Key? key,
    required this.text,
    this.size = 20,
    this.showCopyText = true,
    this.child,
    this.positionY = 40,
    this.positionX = 20,
    this.copyMessageColor,
  }) : super(key: key);

  @override
  // ignore: library_private_types_in_public_api
  _LoginCopyButtonState createState() => _LoginCopyButtonState();
}

class _LoginCopyButtonState extends State<LoginCopyButton> {
  bool _showCheck = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: TextButton.icon(
          icon: _showCheck
              ? ArDriveIcons.checkCirle(
                  size: 24,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeSuccessDefault,
                )
              : ArDriveIcons.copy(
                  size: 24,
                  color:
                      ArDriveTheme.of(context).themeData.colors.themeFgMuted),
          label: Text(
            // TODO: create/update localization keys
            _showCheck ? 'Copied to Clipboard' : 'Copy to Clipboard',
            style: ArDriveTypography.body.smallBold(
                color: ArDriveTheme.of(context).themeData.colors.themeFgMuted),
          ),
          onPressed: _copy,
        ));
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.text));
    if (mounted) {
      if (_showCheck) {
        return;
      }

      setState(() {
        _showCheck = true;

        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) {
            return;
          }

          setState(() {
            _showCheck = false;
          });
        });
      });
    }
  }
}
