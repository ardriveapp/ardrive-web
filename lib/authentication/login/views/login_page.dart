import 'dart:math';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../utils/split_localizations.dart';

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
      child: const LoginPageScaffold(),
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

  late int image;

  @override
  void initState() {
    super.initState();
    image = Random().nextInt(images.length);
  }

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout(
      desktop: Material(
        color: const Color(0xff090A0A),
        child: Row(
          children: [
            Expanded(
              child: _buildIllustration(context, images[image]),
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
                    'Your private, secure, and permanent hard drive.',
                    textAlign: TextAlign.start,
                    style: ArDriveTypography.headline.headline4Regular(
                      // FIXME: This is a hack to get the text to be white
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
          current is! LoginFailure && current is! LoginSuccess,
      listener: (context, state) {
        if (state is LoginFailure) {
          if (state.error is WalletMismatchException) {
            showAnimatedDialog(
              context,
              content: ArDriveIconModal(
                title: 'Login Failed',
                content:
                    'Your ArConnect wallet does not match your ArDrive wallet. Please try again.',
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
              title: 'Login Failed',
              content: 'Please try again.',
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

// Views

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
                'Welcome back!',
                style: ArDriveTypography.headline.headline4Regular(),
              ),
            ),
            Column(
              children: [
                ArDriveDropAreaSingleInput(
                  width: double.maxFinite,
                  dragAndDropDescription: 'Drag & Drop your Keyfile',
                  dragAndDropButtonTitle: 'Browse Json',
                  onDragDone: (file) {
                    context.read<LoginBloc>().add(AddWalletFile(file));
                  },
                  buttonCallback: (file) {
                    context.read<LoginBloc>().add(AddWalletFile(file));
                  },
                  errorDescription: 'Invalid Keyfile',
                  validateFile: (file) async {
                    final wallet = await context
                        .read<LoginBloc>()
                        .validateAndReturnWalletFile(file);

                    return wallet != null;
                  },
                ),
                const SizedBox(
                  height: 24,
                ),
                if (widget.isArConnectAvailable) ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Or continue with',
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
                    const ArDriveCheckBox(title: '', checked: true),
                    Flexible(
                      child: GestureDetector(
                        onTap: () => openUrl(
                          url: 'https://ardrive.io/tos-and-privacy/',
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
              onPressed: () => openUrl(url: 'https://tokens.arweave.org'),
              text: appLocalizationsOf(context).getAWallet,
            ),
          ],
        ),
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
                      autofillHints: const [AutofillHints.password],
                      hintText: 'Enter password',
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
                        // on submit
                      }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ArDriveButton(
                      isDisabled: !_isPasswordValid,
                      onPressed: () {
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
                      },
                      text: 'Proceed',
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
  final _formKey = GlobalKey<FormState>();

  bool _passwordIsValid = false;
  bool _confirmPasswordIsValid = false;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512, maxHeight: 618),
      child: _LoginCard(
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.max,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ArDriveImage(
                image: SvgImage.asset('assets/images/brand/ArDrive-Logo.svg'),
                height: 73,
              ),
              Text(
                'Please create and confirm your password. You will use this password to log in.',
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
    return Column(
      children: [
        ArDriveTextField(
          controller: _passwordController,
          // key: ValueKey(state.autoFocus),
          // autofocus: state.autoFocus,
          showObfuscationToggle: true,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          hintText: 'Enter password',
          onFieldSubmitted: (_) async {
            // on submit
          },
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
          // key: ValueKey(state.autoFocus),
          // autofocus: state.autoFocus,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          hintText: 'Confirm password',
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
          onFieldSubmitted: (_) => _onSubmit(),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ArDriveButton(
            isDisabled:
                _passwordIsValid == false || _confirmPasswordIsValid == false,
            onPressed: _onSubmit,
            text: 'Proceed',
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
    );
  }

  void _onSubmit() {
    // validate if password is not empty
    if (_passwordController.text.isEmpty ||
        _confirmPasswordController.text.isEmpty) {
      showAnimatedDialog(context,
          content: ArDriveIconModal(
            icon: ArDriveIcons.warning(
              size: 88,
              color:
                  ArDriveTheme.of(context).themeData.colors.themeErrorDefault,
            ),
            title: 'Password cannot be empty',
            content: 'Please try again',
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: 'Ok',
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
            title: 'Passwords do not matchr',
            content: 'Please try again',
            actions: [
              ModalAction(
                action: () {
                  Navigator.pop(context);
                },
                title: 'Ok',
              )
            ],
          ));
      return;
    }

    print('passwords match');

    context.read<LoginBloc>().add(
          CreatePassword(
            password: _passwordController.text,
            wallet: widget.wallet,
          ),
        );
  }
}
