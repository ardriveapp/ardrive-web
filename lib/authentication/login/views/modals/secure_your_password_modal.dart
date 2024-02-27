import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';

class SecureYourPasswordWidget extends StatefulWidget {
  const SecureYourPasswordWidget(
      {Key? key,
      required this.loginBloc,
      required this.wallet,
      this.mnemonic,
      required this.showTutorials,
      required this.showWalletCreated})
      : super(key: key);

  final Wallet wallet;
  final String? mnemonic;
  final LoginBloc loginBloc;
  final bool showTutorials;
  final bool showWalletCreated;

  @override
  State<SecureYourPasswordWidget> createState() =>
      _SecureYourPasswordWidgetState();
}

class _SecureYourPasswordWidgetState extends State<SecureYourPasswordWidget> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<ArDriveFormNewState>();
  bool _isPasswordValid = false;
  bool _confirmPasswordIsValid = false;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createAndConfirmPasswordPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.desktop;

    return ArDriveLoginModal(
      width: 450,
      content: ArDriveFormNew(
        key: _formKey,
        child: Column(
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
                'Secure Your Wallet',
                style: typography.heading2(
                    color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Text('Please enter and confirm a password to secure your wallet.',
                style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold)),
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
              onChanged: (s) {
                _formKey.currentState?.validate();
              },
              textInputAction: TextInputAction.next,
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
            ),
            const SizedBox(height: 20),
            Text('Confirm Password',
                style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold)),
            const SizedBox(height: 8),
            ArDriveTextFieldNew(
                controller: _confirmPasswordController,
                hintText: 'Re-enter your password',
                showObfuscationToggle: true,
                obscureText: true,
                autofocus: true,
                autofillHints: const [AutofillHints.password],
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
                onFieldSubmitted: (_) async {
                  if (_isPasswordValid && _confirmPasswordIsValid) {
                    _onSubmit();
                  }
                }),
            const SizedBox(height: 40),
            ArDriveButtonNew(
                text: 'Continue',
                typography: typography,
                variant: ButtonVariant.primary,
                isDisabled: !_isPasswordValid || !_confirmPasswordIsValid,
                onPressed: () {
                  Navigator.of(context).pop();
                  _onSubmit();
                }),
          ],
        ),
      ),
    );
  }

  void _onSubmit() {
    final isValid = _formKey.currentState!.validateSync();

    if (!isValid) {
      showErrorDialog(
          context: context,
          title: appLocalizationsOf(context).error,
          message: appLocalizationsOf(context).passwordDoNotMatch);
      return;
    }

    if (_passwordController.text != _confirmPasswordController.text) {
      showErrorDialog(
          context: context,
          title: appLocalizationsOf(context).error,
          message: appLocalizationsOf(context).passwordDoNotMatch);
      return;
    }

    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.createdAndConfirmedPassword,
    );

    widget.loginBloc.add(
      CreatePassword(
          password: _passwordController.text,
          wallet: widget.wallet,
          mnemonic: widget.mnemonic,
          showTutorials: widget.showTutorials,
          showWalletCreated: widget.showWalletCreated),
    );
  }
}

void showSecureYourPasswordDialog(
    {required BuildContext context,
    required LoginBloc loginBloc,
    required Wallet wallet,
    String? mnemonic,
    required bool showTutorials,
    required bool showWalletCreated}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: SecureYourPasswordWidget(
          loginBloc: loginBloc,
          wallet: wallet,
          mnemonic: mnemonic,
          showTutorials: showTutorials,
          showWalletCreated: showWalletCreated));
}
