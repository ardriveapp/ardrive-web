import 'dart:convert';
import 'dart:html';
import 'dart:io' as io;

import 'package:animations/animations.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive/pages/profile_auth/components/profile_auth_add_screen.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/authentication/biometric_permission_dialog.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/pre_cache_assets.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path_provider/path_provider.dart';
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
          return _FadeThroughTransitionSwitcher(
            fillColor: Colors.transparent,
            child: state is LoginOnBoarding
                ? OnBoardingView(wallet: state.walletFile)
                : const LoginPageScaffold(),
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
    return ScreenTypeLayout(
      desktop: Material(
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
      mobile: Scaffold(
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
    return BlocConsumer<LoginBloc, LoginState>(
      key: globalKey,
      buildWhen: (previous, current) =>
          current is! LoginFailure &&
          current is! LoginSuccess &&
          current is! LoginOnBoarding,
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
        } else if (state is LoginEnterSeedPhrase) {
          content = const EnterSeedPhraseView();
        } else if (state is LoginCreateWallet) {
          content = CreateWalletView(mnemonic: state.mnemonic);
        } else if (state is LoginCreateWalletGenerated) {
          content = CreateWalletView(
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
    return MaxDeviceSizesConstrainedBox(
      defaultMaxWidth: 512,
      defaultMaxHeight: 798,
      maxHeightPercent: 0.9,
      child: _LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ScreenTypeLayout(
              desktop: const SizedBox.shrink(),
              mobile: ArDriveImage(
                image: AssetImage(Resources.images.brand.logo1),
                height: 50,
              ),
            ),
            heightSpacing(),
            Align(
              alignment: Alignment.topCenter,
              child: Text(
                appLocalizationsOf(context).welcome,
                style: ArDriveTypography.headline.headline4Regular(),
              ),
            ),
            heightSpacing(),
            Column(
              children: [
                ArDriveDropAreaSingleInput(
                  controller: _dropAreaController,
                  keepButtonVisible: true,
                  width: double.maxFinite,
                  dragAndDropDescription:
                      appLocalizationsOf(context).dragAndDropDescription,
                  dragAndDropButtonTitle:
                      appLocalizationsOf(context).dragAndDropButtonTitle,
                  errorDescription: appLocalizationsOf(context).invalidKeyFile,
                  validateFile: (file) async {
                    final wallet = await context
                        .read<LoginBloc>()
                        .validateAndReturnWalletFile(file);

                    return wallet != null;
                  },
                  platformSupportsDragAndDrop: !AppPlatform.isMobile,
                ),
                heightSpacing(),
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
                          style: ArDriveTypography.body.smallBold()),
                    ),
                  ),
                ),
                heightSpacing(),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: 'Login with your ',
                          style: ArDriveTypography.body.smallBold(
                            color: ArDriveTheme.of(context)
                                .themeData
                                .colors
                                .themeFgMuted,
                          )),
                      TextSpan(
                        text: 'Seed Phrase',
                        style: ArDriveTypography.body.smallBold().copyWith(
                              decoration: TextDecoration.underline,
                            ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            context.read<LoginBloc>().add(EnterSeedPhrase());
                            // openUrl(url: Resources.getWalletLink);
                          },
                      ),
                    ],
                  ),
                ),
                if (widget.isArConnectAvailable) ...[
                  heightSpacing(),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      appLocalizationsOf(context).orContinueWith,
                      style: ArDriveTypography.body.smallRegular(
                          color: ArDriveTheme.of(context)
                              .themeData
                              .colors
                              .themeFgMuted),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: ArDriveButton(
                            icon: Padding(
                              padding: const EdgeInsets.only(right: 20),
                              child: ArDriveIcons.arconnectIcon1(
                                color: ArDriveTheme.of(context)
                                    .themeData
                                    .colors
                                    .themeFgDefault,
                              ),
                            ),
                            style: ArDriveButtonStyle.secondary,
                            onPressed: () {
                              context
                                  .read<LoginBloc>()
                                  .add(const AddWalletFromArConnect());
                            },
                            text: 'ArConnect',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(
                  height: 24,
                ),
              ],
            ),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                      text: appLocalizationsOf(context).dontHaveAWallet1Part,
                      style: ArDriveTypography.body.smallBold(
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeFgMuted,
                      )),
                  TextSpan(
                    text: appLocalizationsOf(context).dontHaveAWallet2Part,
                    style: ArDriveTypography.body.smallBold().copyWith(
                          decoration: TextDecoration.underline,
                        ),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () {
                        context.read<LoginBloc>().add(CreateWallet());
                        // openUrl(url: Resources.getWalletLink);
                      },
                  ),
                ],
              ),
            ),
          ],
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
  const _LoginCard({required this.content});

  final Widget content;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      double horizontalPadding = 72;

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
        contentPadding: EdgeInsets.fromLTRB(
          horizontalPadding,
          _topPadding(context),
          horizontalPadding,
          _bottomPadding(context),
        ),
        content: content,
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
              ScreenTypeLayout(
                desktop: const SizedBox.shrink(),
                mobile: ArDriveImage(
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
    final isValid = _formKey.currentState!.validate();

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
    return ScreenTypeLayout(
      desktop: Material(
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
      mobile: Scaffold(
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
  const EnterSeedPhraseView();

  // final Wallet wallet;

  @override
  State<EnterSeedPhraseView> createState() => _EnterSeedPhraseViewState();
}

class _EnterSeedPhraseViewState extends State<EnterSeedPhraseView> {
  final _seedPhraseController = TextEditingController();
  final _formKey = GlobalKey<ArDriveFormState>();

  bool _seedPhraseFormatIsValid = false;

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
              ScreenTypeLayout(
                desktop: const SizedBox.shrink(),
                mobile: ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              Text(
                // appLocalizationsOf(context).createAndConfirmPassword,
                'Enter your 12-word mnemonic seed phrase to login.',
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline.headline5Regular(),
              ),
              const SizedBox(height: 16),
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
          ArDriveTextField(
            autofocus: true,
            controller: _seedPhraseController,
            showObfuscationToggle: true,
            obscureText: true,
            // autofillHints: const [AutofillHints.password],
            // hintText: appLocalizationsOf(context).enterPassword,
            hintText: 'Enter Seed Phrase',
            onChanged: (s) {
              _formKey.currentState?.validate();
            },
            textInputAction: TextInputAction.next,
            validator: (value) {
              if (value == null || value.isEmpty) {
                setState(() {
                  _seedPhraseFormatIsValid = false;
                });
                return appLocalizationsOf(context).validationRequired;
              } else if (!bip39.validateMnemonic(value)) {
                setState(() {
                  _seedPhraseFormatIsValid = false;
                });
                // FIXME - localize
                return 'Please enter a valid 12-word mnemonic.';
                // return appLocalizationsOf(context).validationRequired;
              }

              setState(() {
                _seedPhraseFormatIsValid = true;
              });

              return null;
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              isDisabled: !_seedPhraseFormatIsValid,
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
    final isValid = _formKey.currentState!.validate();

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

    context
        .read<LoginBloc>()
        .add(AddWalletFromMnemonic(_seedPhraseController.text));
  }
}

class CreateWalletView extends StatefulWidget {
  const CreateWalletView({super.key, required this.mnemonic, this.wallet});

  final String mnemonic;
  final Wallet? wallet;

  @override
  State<CreateWalletView> createState() => _CreateWalletViewState();
}

class _CreateWalletViewState extends State<CreateWalletView> {
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
              ScreenTypeLayout(
                desktop: const SizedBox.shrink(),
                mobile: ArDriveImage(
                  image: AssetImage(Resources.images.brand.logo1),
                  height: 50,
                ),
              ),
              Text(
                // appLocalizationsOf(context).createAndConfirmPassword,
                'Record your 12-word mnemonic wallet seed phrase.',
                textAlign: TextAlign.center,
                style: ArDriveTypography.headline.headline5Regular(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                  enabled: false,
                  controller: TextEditingController(text: widget.mnemonic),
                  maxLines: 2),
              const SizedBox(height: 16),
              ArDriveButton(
                isDisabled: widget.wallet == null,
                onPressed: () {
                  _onDownload();
                },
                // FIXME - localize
                text: widget.wallet == null
                    ? 'Generating Wallet File...'
                    : 'Download Wallet File',
              ),
              const SizedBox(height: 16),
              ArDriveButton(
                isDisabled: widget.wallet == null,
                onPressed: () {
                  // _onSubmit();
                },
                text: appLocalizationsOf(context).proceed,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onDownload() async {
    if (widget.wallet != null) {
      final jsonTxt = jsonEncode(widget.wallet!.toJwk());
      if (kIsWeb) {
        final anchor = AnchorElement(
            href: 'data:application/text/plain;charset=utf-8,$jsonTxt');
        anchor.download = 'ardrive-wallet.json';
        // trigger download
        document.body!.append(anchor);
        anchor.click();
        anchor.remove();
      } else {
        final directory = await getApplicationDocumentsDirectory();
        final f = io.File('$directory/ardrive-wallet.json');
        f.writeAsStringSync(jsonTxt);
      }
    }
  }
}
