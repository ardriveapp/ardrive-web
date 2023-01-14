import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/user/services/user_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:responsive_builder/responsive_builder.dart';

import '../../../utils/split_localizations.dart';

class LoginPageScaffold extends StatelessWidget {
  const LoginPageScaffold({
    super.key,
    required this.content,
  });

  final Widget content;

  @override
  Widget build(BuildContext context) {
    return ScreenTypeLayout(
      desktop: Material(
        color: const Color(0xff090A0A),
        child: Row(
          children: [
            Expanded(
              child: _buildIllustration(context),
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

  Widget _buildIllustration(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          // Container(
          const Opacity(
            opacity: 0.25,
            child: ArDriveImage(
              image: AssetImage(
                'assets/images/login/photo-1604684116250-e79276b241fd.png',
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

  Widget _buildContent(BuildContext context) {
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
  }
}

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
        arDriveAuth: ArDriveAuth(
          userService: UserService(
            context.read<ProfileDao>(),
          ),
          arweave: arweave,
        ),
      )..add(const CheckIfUserIsLoggedIn()),
      child: BlocConsumer<LoginBloc, LoginState>(
        buildWhen: (previous, current) =>
            current is! LoginFailure && current is! LoginSuccess,
        listener: (context, state) {
          if (state is LoginFailure) {
            showAnimatedDialog(
              context,
              content: ArDriveIconModal(
                title: 'Login Failed',
                content: 'Please try again.',
                icon: ArDriveIcons.warning(
                  size: 88,
                  color: ArDriveTheme.of(context)
                      .themeData
                      .colors
                      .themeErrorDefault,
                ),
              ),
            );
          } else if (state is LoginSuccess) {
            context.read<ProfileCubit>().unlockDefaultProfile(
                state.user.password, state.user.profileType);
          }
        },
        builder: (context, state) {
          if (state is PromptPassword) {
            return LoginPageScaffold(
              content: PromptPasswordView(
                wallet: state.walletFile,
              ),
            );
          } else if (state is CreatingNewPassword) {
            return LoginPageScaffold(
              content: CreatePasswordView(
                wallet: state.walletFile,
              ),
            );
          } else if (state is LoginLoading) {
            return LoginPageScaffold(
              content: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: 512, maxHeight: 489),
                child: const _LoginCard(
                  content: Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
            );
          }
          return const LoginPageScaffold(
            content: PromptWalletView(),
          );
        },
      ),
    );
  }
}

class PromptWalletView extends StatefulWidget {
  const PromptWalletView({super.key});

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
                          style: ArDriveButtonStyle.secondary,
                          onPressed: () {},
                          text: 'ArConnect',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(
                  height: 24,
                ),
                Row(
                  children: [
                    const ArDriveCheckBox(title: ''),
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
                      controller: _passwordController,
                      // key: ValueKey(state.autoFocus),
                      // autofocus: state.autoFocus,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      hintText: 'Enter password',
                      errorMessage:
                          appLocalizationsOf(context).validationRequired,
                      onFieldSubmitted: (_) async {
                        // on submit
                      }),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ArDriveButton(
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
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          hintText: 'Enter password',
          errorMessage: appLocalizationsOf(context).validationRequired,
          onFieldSubmitted: (_) async {
            // on submit
          },
          validator: (value) {
            if (value == null || value.isEmpty) {
              return false;
            }
            return true;
          },
        ),
        const SizedBox(height: 16),
        ArDriveTextField(
          controller: _confirmPasswordController,
          // key: ValueKey(state.autoFocus),
          // autofocus: state.autoFocus,
          obscureText: true,
          autofillHints: const [AutofillHints.password],
          hintText: 'Confirm password',
          validator: (value) {
            if (value != _passwordController.text) {
              return false;
            }
            return true;
          },
          errorMessage: appLocalizationsOf(context).validationRequired,
          onFieldSubmitted: (_) async {
            // on submit
          },
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ArDriveButton(
            onPressed: () {
              // validate if password is not empty
              if (_passwordController.text.isEmpty ||
                  _confirmPasswordController.text.isEmpty) {
                showAnimatedDialog(context,
                    content: ArDriveIconModal(
                      icon: ArDriveIcons.warning(
                        size: 88,
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeErrorDefault,
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
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeErrorDefault,
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

              context.read<LoginBloc>().add(
                    CreatePassword(
                      password: _passwordController.text,
                      wallet: widget.wallet,
                    ),
                  );
            },
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
}
