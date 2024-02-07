import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/components/truncated_address_new.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';

class EnterYourPasswordWidget extends StatefulWidget {
  const EnterYourPasswordWidget(
      {Key? key, required this.loginBloc, this.wallet})
      : super(key: key);

  final Wallet? wallet;
  final LoginBloc loginBloc;

  @override
  State<EnterYourPasswordWidget> createState() =>
      _EnterYourPasswordWidgetState();
}

class _EnterYourPasswordWidgetState extends State<EnterYourPasswordWidget> {
  final _passwordController = TextEditingController();
  // final _formKey = GlobalKey<ArDriveFormState>();
  bool _isPasswordValid = false;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.desktop;

    return ArDriveLoginModal(
      width: 450,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(appLocalizationsOf(context).walletAddress,
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(width: 8),
              FutureBuilder(
                  future: widget.wallet?.getAddress(),
                  builder: (context, address) => address.hasData
                      ? TruncatedAddressNew(walletAddress: address.data!)
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
          const SizedBox(height: 40),
          ArDriveButtonNew(
              text: 'Continue',
              typography: typography,
              variant: ButtonVariant.primary,
              isDisabled: !_isPasswordValid,
              onPressed: () {
                if (_isPasswordValid) {
                  Navigator.of(context).pop();
                  _onSubmit();
                }
                // if (_formKey.currentState!.validate()) {
                //   Navigator.of(context).pop();
                //   // showImportWalletDialog(context);
                // }
              }),
        ],
      ),
    );
  }

  void _onSubmit() {
    if (widget.wallet == null) {
      widget.loginBloc.add(UnlockUserWithPassword(
        password: _passwordController.text,
      ));
    } else {
      widget.loginBloc.add(LoginWithPassword(
        password: _passwordController.text,
        wallet: widget.wallet!,
      ));
    }
  }
}

void showEnterYourPasswordDialog(
    {required BuildContext context,
    required LoginBloc loginBloc,
    Wallet? wallet}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: EnterYourPasswordWidget(loginBloc: loginBloc, wallet: wallet));
}
