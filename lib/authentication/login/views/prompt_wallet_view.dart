import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/lined_text_divider.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/import_wallet_modal.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

import '../../../misc/resources.dart';
import '../../components/login_card.dart';
import '../../components/max_device_sizes_constrained_box.dart';

const String termsOfServiceUrl = 'https://ardrive.io/tos-and-privacy/';

class PromptWalletView extends StatefulWidget {
  final bool isArConnectAvailable;
  final bool isMetamaskAvailable;
  final bool existingUserFlow;

  const PromptWalletView({
    super.key,
    required this.isArConnectAvailable,
    required this.isMetamaskAvailable,
    required this.existingUserFlow,
  });

  @override
  State<PromptWalletView> createState() => _PromptWalletViewState();
}

class _PromptWalletViewState extends State<PromptWalletView> {
  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final existingUserFlow = widget.existingUserFlow;

    final width = MediaQuery.of(context).size.width;

    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          MaxDeviceSizesConstrainedBox(
            defaultMaxWidth: 381,
            defaultMaxHeight: 798,
            maxHeightPercent: 1.0,
            child: LoginCard(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ArDriveImage(
                    image: AssetImage(Resources.images.brand.logo1),
                    height: 50,
                  ),
                  heightSpacing(),
                  Text(
                    // FIXME: Add localization key
                    'Welcome to ArDrive',
                    textAlign: TextAlign.center,
                    style: typography.heading1(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.bold),
                  ),

                  heightSpacing(),
                  //FIXME: Add localization key
                  Text(
                    widget.existingUserFlow
                        ? 'Sign in using one of the options below.'
                        : 'To use ArDrive you need a wallet. A wallet is a new way to log in. Instead of creating usernames and passwords, just connect your wallet.',
                    style: typography.paragraphLarge(
                        color: colorTokens.textLow,
                        fontWeight: ArFontWeight.semiBold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 72),
                  if (widget.isArConnectAvailable ||
                      widget.isMetamaskAvailable) ...[
                    if (widget.isArConnectAvailable) ...[
                      ArDriveButtonNew(
                          text: 'Continue with ArConnect',
                          hoverIcon: Container(
                              alignment: Alignment.center,
                              child: ArDriveImage(
                                width: 24,
                                height: 24,
                                image: SvgImage.asset(
                                    Resources.images.login.arconnectLogo),
                              )),
                          typography: typography,
                          onPressed: () {
                            context
                                .read<LoginBloc>()
                                .add(const AddWalletFromArConnect());
                          }),
                      const SizedBox(height: 16),
                    ],
                    if (widget.isMetamaskAvailable) ...[
                      ArDriveButtonNew(
                          text: 'Continue with MetaMask',
                          hoverIcon: Container(
                              alignment: Alignment.center,
                              child: SvgPicture.asset(
                                Resources.images.login.metamask,
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                              )),
                          typography: typography,
                          onPressed: () {
                            context
                                .read<LoginBloc>()
                                .add(const LoginWithMetamask());
                          }),
                    ],
                    const SizedBox(height: 40),
                    const LinedTextDivider(text: 'or'),
                  ],
                  const SizedBox(height: 40),
                  existingUserFlow
                      ? ArDriveButtonNew(
                          text: 'Import Wallet',
                          hoverIcon: Container(
                              alignment: Alignment.center,
                              child: SvgPicture.asset(
                                Resources.images.login.walletUpload,
                                width: 24,
                                height: 24,
                                fit: BoxFit.contain,
                              )),
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
                            context
                                .read<LoginBloc>()
                                .add(const CreateNewWallet());
                          }),
                  const SizedBox(height: 72),
                  // TODO:  make this into a reusable component
                  Text.rich(
                    textAlign: TextAlign.center,
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
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              RichText(
                textAlign: TextAlign.center,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text:
                          'By connecting your wallet, you agree to our ${width < TABLET ? '\n' : ''}',
                      style: typography.paragraphNormal(
                          color: colorTokens.textLow,
                          fontWeight: ArFontWeight.semiBold),
                    ),
                    TextSpan(
                      text: 'Terms of Service',
                      style: typography
                          .paragraphNormal(
                            color: colorTokens.textLink,
                            fontWeight: ArFontWeight.bold,
                          )
                          .copyWith(decoration: TextDecoration.underline),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () {
                          openUrl(url: termsOfServiceUrl);
                        },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ],
      ),
    );
  }

  SizedBox heightSpacing() {
    return SizedBox(
        height: MediaQuery.of(context).size.height < 700 ? 12.0 : 16.0);
  }
}
