import 'package:ardrive/authentication/components/breakpoint_layout_builder.dart';
import 'package:ardrive/authentication/components/lined_text_divider.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/import_wallet_modal.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
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
  void initState() {
    super.initState();
    if (widget.existingUserFlow) {
      PlausibleEventTracker.trackPageview(page: PlausiblePageView.loginPage);
    } else {
      PlausibleEventTracker.trackPageview(page: PlausiblePageView.signUpPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);
    final existingUserFlow = widget.existingUserFlow;

    final width = MediaQuery.of(context).size.width;

    final pageView = existingUserFlow
        ? PlausiblePageView.loginPage
        : PlausiblePageView.signUpPage;

    return SizedBox.expand(
      child: Stack(
        alignment: Alignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: MaxDeviceSizesConstrainedBox(
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
                          text: 'Continue with Wander',
                          hoverIcon: Container(
                              alignment: Alignment.center,
                              child: ArDriveImage(
                                width: 24,
                                height: 24,
                                image: SvgImage.asset(
                                    Resources.images.login.wanderLogo),
                              )),
                          typography: typography,
                          onPressed: () {
                            PlausibleEventTracker
                                .trackClickContinueWithArconnectButton(
                              pageView,
                            );

                            context
                                .read<LoginBloc>()
                                .add(const AddWalletFromArConnect());
                          },
                        ),
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
                            ),
                          ),
                          typography: typography,
                          onPressed: () {
                            PlausibleEventTracker
                                .trackClickContinueWithMetamaskButton(
                              pageView,
                            );

                            context
                                .read<LoginBloc>()
                                .add(const LoginWithMetamask());
                          },
                        ),
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
                              PlausibleEventTracker
                                  .trackClickImportWalletButton();

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
                              PlausibleEventTracker.trackClickCreateWallet();
                              context
                                  .read<LoginBloc>()
                                  .add(const CreateNewWallet());
                            }),
                    const SizedBox(height: 72),
                    // TODO:  make this into a reusable component
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IntrinsicWidth(
                          child: Column(
                            children: [
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: widget.existingUserFlow
                                          ? "I'm a new user"
                                          : 'I already have a wallet',
                                      // Your TextStyle here
                                      style: typography.paragraphLarge(
                                          color: colorTokens.textLink,
                                          fontWeight: ArFontWeight.semiBold),
                                      recognizer: TapGestureRecognizer()
                                        ..onTap = () {
                                          if (widget.existingUserFlow) {
                                            PlausibleEventTracker
                                                .trackClickImANewUserLinkButton();
                                          } else {
                                            PlausibleEventTracker
                                                .trackClickAlreadyHaveAWallet();
                                          }

                                          context.read<LoginBloc>().add(
                                              SelectLoginFlow(
                                                  existingUser: !widget
                                                      .existingUserFlow));
                                        },
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Container(
                                height: 1,
                                color: colorTokens.buttonPrimaryDefault,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.shadow,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: RichText(
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
                        style: typography.paragraphNormal(
                          color: colorTokens.textLink,
                          fontWeight: ArFontWeight.bold,
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap = () {
                            PlausibleEventTracker.trackClickTermsOfServices(
                              pageView,
                            );
                            openUrl(url: termsOfServiceUrl);
                          },
                      ),
                    ],
                  ),
                ),
              ),
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
