import 'dart:math';

import 'package:animations/animations.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/split_localizations.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

// TODO: Remove hardcoded colors and replace with design tokens
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
      child: BlocBuilder<LoginBloc, LoginState>(
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
  final images = [
    Resources.images.login.login1,
    Resources.images.login.login2,
    Resources.images.login.login3,
    Resources.images.login.login4,
  ];

  late int imageIndex;

  @override
  void initState() {
    super.initState();
    imageIndex = Random().nextInt(images.length);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout(
      desktop: Material(
        color: const Color(0xff090A0A),
        child: Row(
          children: [
            Expanded(
              child: _buildIllustration(context, images[imageIndex]),
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
            padding: const EdgeInsets.all(16.0),
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
        // Container(
        Opacity(
          opacity: 0.25,
          child: ArDriveImage(
            key: const Key('loginPageIllustration'),
            image: AssetImage(
              image,
            ),
            fit: BoxFit.cover,
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
                      ? Resources.images.brand.logoHorizontalNoSubtitleLight
                      : Resources.images.brand.logoHorizontalNoSubtitleDark,
                ),
                height: 65,
                fit: BoxFit.contain,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 42),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width * 0.25,
                  child: Text(
                    appLocalizationsOf(context)
                        .yourPrivateSecureAndPermanentDrive,
                    textAlign: TextAlign.start,
                    style: ArDriveTypography.headline.headline4Regular(
                      color: const Color(0xffFAFAFA),
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
      buildWhen: (previous, current) =>
          current is! LoginFailure &&
          current is! LoginSuccess &&
          current is! LoginOnBoarding,
      listener: (context, state) {
        if (state is LoginFailure) {
          if (state.error is WalletMismatchException) {
            showAnimatedDialog(
              context,
              content: ArDriveIconModal(
                title: appLocalizationsOf(context).loginFailed,
                content: appLocalizationsOf(context)
                    .arConnectWalletDoestNotMatchArDriveWallet,
                icon: ArDriveIcons.warning(
                  size: 88,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeErrorDefault,
                ),
              ),
            );
            return;
          }
          showAnimatedDialog(
            context,
            content: ArDriveIconModal(
              title: appLocalizationsOf(context).loginFailed,
              content: appLocalizationsOf(context).pleaseTryAgain,
              icon: ArDriveIcons.warning(
                size: 88,
                color:
                    ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
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
          content = ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512, maxHeight: 489),
            child: const _LoginCard(
              content: Center(
                child: CircularProgressIndicator(),
              ),
            ),
          );
        } else {
          content = PromptWalletView(
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
  bool _isTermsChecked = true;
  IOFile? _file;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512, maxHeight: 798),
      child: _LoginCard(
        content: Column(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: Text(
                appLocalizationsOf(context).welcomeBack,
                style: ArDriveTypography.headline.headline4Regular(),
              ),
            ),
            Column(
              children: [
                ArDriveDropAreaSingleInput(
                  width: double.maxFinite,
                  dragAndDropDescription:
                      appLocalizationsOf(context).dragAndDropDescription,
                  dragAndDropButtonTitle:
                      appLocalizationsOf(context).dragAndDropButtonTitle,
                  onDragDone: (file) {
                    _file = file;
                    if (!_isTermsChecked) {
                      showAnimatedDialog(context,
                          content: _showAcceptTermsModal());
                      return;
                    }
                    context.read<LoginBloc>().add(AddWalletFile(file));
                  },
                  buttonCallback: (file) {
                    _file = file;

                    if (!_isTermsChecked) {
                      showAnimatedDialog(context,
                          content: _showAcceptTermsModal());
                    }

                    context.read<LoginBloc>().add(AddWalletFile(file));
                  },
                  errorDescription: appLocalizationsOf(context).invalidKeyFile,
                  validateFile: (file) async {
                    final wallet = await context
                        .read<LoginBloc>()
                        .validateAndReturnWalletFile(file);

                    return wallet != null;
                  },
                  platformSupportsDragAndDrop: !AppPlatform.isMobile,
                ),
                const SizedBox(
                  height: 24,
                ),
                if (widget.isArConnectAvailable) ...[
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
                              child: ArDriveImage(
                                height: 24,
                                width: 22,
                                image: AssetImage(
                                  const Images().login.arconnectLogo,
                                ),
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
                Row(
                  children: [
                    ArDriveCheckBox(
                        title: '',
                        checked: _isTermsChecked,
                        onChange: ((value) {
                          if (_file != null && value) {
                            context
                                .read<LoginBloc>()
                                .add(AddWalletFile(_file!));
                          }
                          setState(() => _isTermsChecked = value);
                        })),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => openUrl(
                          url: Resources.agreementLink,
                        ),
                        child: Text.rich(
                          TextSpan(
                            children:
                                splitTranslationsWithMultipleStyles<InlineSpan>(
                              originalText: appLocalizationsOf(context)
                                  .aggreeToTerms_body,
                              defaultMapper: (text) => TextSpan(text: text),
                              parts: {
                                appLocalizationsOf(context).aggreeToTerms_link:
                                    (text) => TextSpan(
                                          text: text,
                                          style: const TextStyle(
                                            decoration:
                                                TextDecoration.underline,
                                          ),
                                        ),
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ArDriveTextButton(
              onPressed: () => openUrl(url: Resources.getWalletLink),
              text: appLocalizationsOf(context).getAWallet,
            ),
          ],
        ),
      ),
    );
  }

  Widget _showAcceptTermsModal() {
    return ArDriveIconModal(
      title: appLocalizationsOf(context).termsAndConditions,
      content: appLocalizationsOf(context).pleaseAcceptTheTermsToContinue,
      icon: ArDriveIcons.warning(
        size: 88,
        color: ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({super.key, required this.content});

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
        borderRadius: 24,
        boxShadow: BoxShadowCard.shadow80,
        contentPadding: EdgeInsets.fromLTRB(
          horizontalPadding,
          53,
          horizontalPadding,
          43,
        ),
        content: content,
      );
    });
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512, maxHeight: 489),
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
                      text:
                          appLocalizationsOf(context).proceedUnlockWithPassword,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: ArDriveButton(
                  onPressed: () {
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
                      content:
                          appLocalizationsOf(context).forgetWalletDescription,
                      actions: actions,
                    );
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

  bool _passwordIsValid = false;
  bool _confirmPasswordIsValid = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512, maxHeight: 618),
      child: _LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ArDriveImage(
              image: SvgImage.asset('assets/images/brand/ArDrive-Logo.svg'),
              height: 73,
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
              if (_passwordIsValid && _confirmPasswordIsValid) {
                _onSubmit();
              }
            },
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ArDriveButton(
              isDisabled:
                  _passwordIsValid == false || _confirmPasswordIsValid == false,
              onPressed: _onSubmit,
              text: appLocalizationsOf(context).proceedCreatePassword,
            ),
          ),
          const SizedBox(
            height: 53,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ArDriveButton(
              onPressed: () {
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
                  content: appLocalizationsOf(context).forgetWalletDescription,
                  actions: actions,
                );
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
            icon: ArDriveIcons.warning(
              size: 88,
              color:
                  ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
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
            icon: ArDriveIcons.warning(
              size: 88,
              color:
                  ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
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
          illustration:
              AssetImage(Resources.images.login.onboarding.onboarding6),
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
          illustration:
              AssetImage(Resources.images.login.onboarding.onboarding2),
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
          title: appLocalizationsOf(context).onboarding3Title,
          description: appLocalizationsOf(context).onboarding3Description,
          illustration:
              AssetImage(Resources.images.login.onboarding.onboarding5),
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
          title: appLocalizationsOf(context).onboarding4Title,
          description: appLocalizationsOf(context).onboarding4Description,
          illustration:
              AssetImage(Resources.images.login.onboarding.onboarding4),
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
          title: appLocalizationsOf(context).onboarding5Title,
          description: appLocalizationsOf(context).onboarding5Description,
          illustration:
              AssetImage(Resources.images.login.onboarding.onboarding3),
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout(
      desktop: Material(
        color: const Color(0xff090A0A),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Container(
                color: const Color(0xff1F1F1F),
                child: Align(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: 512, maxHeight: 489),
                    child: _FadeThroughTransitionSwitcher(
                        fillColor: const Color(0xff1F1F1F),
                        child: _buildOnBoardingContent()),
                  ),
                ),
              ),
            ),
            Expanded(
              child: FractionallySizedBox(
                widthFactor: 0.5,
                child: Center(child: _buildOnBoardingIllustration()),
              ),
            ),
          ],
        ),
      ),
      mobile: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Container(
          color: const Color(0xff1F1F1F),
          child: Align(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 512, maxHeight: 489),
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

  Widget _buildOnBoardingIllustration() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // image
        ArDriveImage(
          image: _list[_currentPage].illustration,
          height: 272,
          width: 372,
        ),
        const SizedBox(
          height: 92,
        ),
        // pagination dots
        ArDrivePaginationDots(
          currentPage: _currentPage,
          numberOfPages: _list.length,
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
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                  ? ArDriveIcons.arrowLeftCircle()
                  : null,
              style: ArDriveButtonStyle.secondary,
              text: onBoarding.secundaryButtonText,
              onPressed: () => onBoarding.secundaryButtonAction(),
            ),
            const SizedBox(width: 32),
            ArDriveButton(
              iconAlignment: IconButtonAlignment.right,
              icon: ArDriveIcons.arrowRightCircle(),
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
          fillColor: const Color(0xff1F1F1F),
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        );
      },
      child: child,
    );
  }
}
