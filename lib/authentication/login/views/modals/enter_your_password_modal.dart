import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/authentication/components/biometric_toggle.dart';
import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/components/truncated_address_new.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class EnterYourPasswordWidget extends StatefulWidget {
  const EnterYourPasswordWidget({
    Key? key,
    required this.loginBloc,
    this.wallet,
    this.derivedEthWallet,
    required this.showWalletCreated,
    required this.alreadyLoggedIn,
    required this.checkingPassword,
    required this.passwordFailed,
  }) : super(key: key);

  final Wallet? wallet;
  final EthereumProviderWallet? derivedEthWallet;
  final LoginBloc loginBloc;
  final bool showWalletCreated;
  final bool alreadyLoggedIn;
  final bool checkingPassword;
  final bool passwordFailed;

  @override
  State<EnterYourPasswordWidget> createState() =>
      _EnterYourPasswordWidgetState();
}

class _EnterYourPasswordWidgetState extends State<EnterYourPasswordWidget> {
  final _passwordController = TextEditingController();
  // final _formKey = GlobalKey<ArDriveFormState>();
  bool _isPasswordValid = false;
  bool _isPasswordFailed = false;

  @override
  void initState() {
    super.initState();
    _isPasswordFailed = widget.passwordFailed;
    PlausibleEventTracker.trackPageview(
      page: _getPlausiblePageView(),
    );
  }

  PlausiblePageView _getPlausiblePageView() {
    if (widget.alreadyLoggedIn) {
      return PlausiblePageView.returnUserPage;
    } else {
      return PlausiblePageView.enterPasswordPage;
    }
  }

  @override
  void didUpdateWidget(EnterYourPasswordWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    setState(() {
      _isPasswordFailed = widget.passwordFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final showDerivedWalletAlreadyCreated =
        widget.derivedEthWallet != null && !widget.loginBloc.existingUserFlow;

    return SingleChildScrollView(
      child: ArDriveLoginModal(
        width: 450,
        hasCloseButton: !widget.alreadyLoggedIn,
        onClose: !widget.alreadyLoggedIn
            ? () {
                PlausibleEventTracker.trackClickDismissLoginModalIcon(
                  _getPlausiblePageView(),
                );
                Navigator.of(context).pop();
                widget.loginBloc.add(const ForgetWallet());
              }
            : null,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
                child: ArDriveImage(
              image: AssetImage(Resources.images.brand.logo1),
              height: 36,
            )),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.topCenter,
              child: Text(
                'Enter Your Password',
                style: typography.heading2(
                    color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            showDerivedWalletAlreadyCreated
                ? Text(
                    'We found a wallet already created for this Ethereum address, please enter your password to continue.',
                    textAlign: TextAlign.center,
                    style: typography.paragraphNormal(
                        color: colorTokens.textLow,
                        fontWeight: ArFontWeight.semiBold),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(appLocalizationsOf(context).walletAddress,
                          style: typography.paragraphNormal(
                              color: colorTokens.textLow,
                              fontWeight: ArFontWeight.semiBold)),
                      const SizedBox(width: 8),
                      FutureBuilder(
                          future: _getWalletAddress(),
                          builder: (context, address) => address.hasData
                              ? TruncatedAddressNew(
                                  walletAddress: address.data!)
                              : const Text(''))
                    ],
                  ),
            const SizedBox(height: 40),
            Text('Password',
                style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold)),
            const SizedBox(height: 8),
            ArDriveTextFieldNew(
              controller: _passwordController,
              hintText: 'Enter your password',
              showObfuscationToggle: true,
              obscureText: true,
              autofocus: true,
              autofillHints: const [AutofillHints.password],
              isEnabled: !widget.checkingPassword,
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
                  PlausibleEventTracker.trackPressEnterContinueReturnUser();
                  _onSubmit();
                }
              },
              onChanged: (_) {
                setState(() {
                  _isPasswordFailed = false;
                });
              },
              errorMessage: 'Invalid password. Please try again.',
              showErrorMessage: _isPasswordFailed,
            ),
            Align(
              alignment: Alignment.center,
              child: BiometricToggle(
                padding: const EdgeInsets.only(top: 40),
                onEnableBiometric: () {
                  context.read<LoginBloc>().add(const UnLockWithBiometrics());
                },
              ),
            ),
            const Flexible(child: SizedBox(height: 40)),
            ArDriveButtonNew(
                text: 'Continue',
                typography: typography,
                variant: ButtonVariant.primary,
                isDisabled: !_isPasswordValid || widget.checkingPassword,
                onPressed: () {
                  if (_isPasswordValid) {
                    if (widget.alreadyLoggedIn) {
                      PlausibleEventTracker
                          .trackClickContinueReturnUserButton();
                    } else {
                      PlausibleEventTracker.trackClickContinueLoginButton();
                    }

                    _onSubmit();
                  }
                }),
            if (widget.alreadyLoggedIn) ...[
              const SizedBox(height: 40),
              Text.rich(
                textAlign: TextAlign.center,
                TextSpan(
                  children: [
                    TextSpan(
                      // TODO: create/update localization key
                      text: appLocalizationsOf(context).forgetWallet,
                      style: typography.paragraphLarge(
                          color: colorTokens.textLow,
                          fontWeight: ArFontWeight.semiBold),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          Navigator.of(context).pop();
                          widget.loginBloc.add(const ForgetWallet());
                          PlausibleEventTracker
                              .trackClickForgetWalletTextButton();
                        },
                    ),
                  ],
                ),
              )
            ]
          ],
        ),
      ),
    );
  }

  Future<String?> _getWalletAddress() async {
    if (widget.wallet == null) {
      return context.read<ArDriveAuth>().getWalletAddress();
    }
    return widget.wallet!.getAddress();
  }

  void _onSubmit() {
    if (widget.wallet == null) {
      widget.loginBloc.add(UnlockUserWithPassword(
        password: _passwordController.text,
      ));
    } else {
      if (widget.wallet is EthereumProviderWallet) {
        Navigator.of(context).pop();
      }
      widget.loginBloc.add(LoginWithPassword(
          password: _passwordController.text,
          wallet: widget.wallet!,
          derivedEthWallet: widget.derivedEthWallet,
          showWalletCreated: widget.showWalletCreated));
    }
  }
}

void showEnterYourPasswordDialog(
    {required BuildContext context,
    required LoginBloc loginBloc,
    required bool alreadyLoggedIn,
    Wallet? wallet,
    EthereumProviderWallet? derivedEthWallet,
    bool showWalletCreated = false,
    required bool isPasswordInvalid}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: BlocBuilder(
        bloc: loginBloc,
        buildWhen: (previous, current) {
          if (current is LoginSuccess) {
            Navigator.of(context).pop();
            return false;
          }
          return (current is LoginCheckingPassword ||
              current is LoginPasswordFailed ||
              current is LoginWithPassword);
        },
        builder: (context, state) {
          final checkingPassword = state is LoginCheckingPassword;
          final passwordFailed =
              state is LoginPasswordFailed || isPasswordInvalid;

          return EnterYourPasswordWidget(
            loginBloc: loginBloc,
            wallet: wallet,
            derivedEthWallet: derivedEthWallet,
            showWalletCreated: showWalletCreated,
            alreadyLoggedIn: alreadyLoggedIn,
            checkingPassword: checkingPassword,
            passwordFailed: passwordFailed,
          );
        },
      ));
}
