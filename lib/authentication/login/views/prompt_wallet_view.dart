import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/lined_text_divider.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/import_wallet_modal.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../misc/resources.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';

class PromptWalletView extends StatefulWidget {
  final bool isArConnectAvailable;
  final bool existingUserFlow;

  const PromptWalletView({
    super.key,
    required this.isArConnectAvailable,
    required this.existingUserFlow,
  });

  @override
  State<PromptWalletView> createState() => _PromptWalletViewState();
}

class _PromptWalletViewState extends State<PromptWalletView> {
  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final existingUserFlow = widget.existingUserFlow;

    // FIXME: add switching of typography based on screen size
    final typography = ArDriveTypographyNew.desktop;

    return MaxDeviceSizesConstrainedBox(
      defaultMaxWidth: 512,
      defaultMaxHeight: 798,
      maxHeightPercent: 0.9,
      child: SingleChildScrollView(
        child: LoginCard(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ArDriveImage(
                image: AssetImage(Resources.images.brand.logo1),
                height: 50,
              ),
              heightSpacing(),
              Align(
                alignment: Alignment.topCenter,
                child: Text(
                  // FIXME: Add localization key
                  'Welcome to ArDrive',
                  style: typography.heading1(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold),
                ),
              ),
              heightSpacing(),
              //FIXME: Add localization key
              Text(
                  widget.existingUserFlow
                      ? 'Sign in using one of the options below.'
                      : 'To use ArDrive you need a wallet. A wallet is a new way to log in. Instead of creating usernames and passwords, just connect your wallet.',
                  style: typography.paragraphLarge(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 72),
              // TODO: Check if we need to do the same for ArConnect as in the past

              if (widget.isArConnectAvailable) ...[
                ArDriveButtonNew(
                    text: 'Continue with ArConnect',
                    typography: typography,
                    maxWidth: double.maxFinite,
                    onPressed: () {
                      context
                          .read<LoginBloc>()
                          .add(const AddWalletFromArConnect());
                    })
              ],
              const SizedBox(height: 16),
              ArDriveButtonNew(
                  text: 'Continue with MetaMask',
                  typography: typography,
                  maxWidth: double.maxFinite,
                  onPressed: () {
                    // print('Implement me!');
                  }),
              const SizedBox(height: 40),
              const LinedTextDivider(text: 'or'),
              const SizedBox(height: 40),
              existingUserFlow
                  ? ArDriveButtonNew(
                      text: 'Import Wallet',
                      typography: typography,
                      maxWidth: double.maxFinite,
                      onPressed: () {
                        showImportWalletDialog(
                            context: context,
                            loginBloc: context.read<LoginBloc>());
                      })
                  : ArDriveButtonNew(
                      text: 'Create a Wallet',
                      typography: typography,
                      variant: ButtonVariant.primary,
                      maxWidth: double.maxFinite,
                      onPressed: () {
                        // print('Implement me!');
                      }),
              const SizedBox(height: 72),
              // TODO:  make this into a reusable component
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      // TODO: create/update localization key
                      text: widget.existingUserFlow
                          ? "I'm a new user"
                          : 'I already have a wallet',
                      style: typography.paragraphLarge(
                          color: colorTokens.textLink,
                          fontWeight: ArFontWeight.semiBold),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          context.read<LoginBloc>().add(SelectLoginFlow(
                              existingUser: !widget.existingUserFlow));
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
        height: MediaQuery.of(context).size.height < 700 ? 12.0 : 16.0);
  }
}
