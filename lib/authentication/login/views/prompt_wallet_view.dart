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
  // late ArDriveDropAreaSingleInputController _dropAreaController;

  @override
  void initState() {
    // _dropAreaController = ArDriveDropAreaSingleInputController(
    //   onFileAdded: (file) {
    //     context.read<LoginBloc>().add(AddWalletFile(file));
    //   },
    //   validateFile: (file) async {
    //     final wallet =
    //         await context.read<LoginBloc>().validateAndReturnWalletFile(file);

    //     return wallet != null;
    //   },
    //   onDragEntered: () {},
    //   onDragExited: () {},
    //   onError: (Object e) {},
    // );

    super.initState();
  }

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
                    print('Implement me!');
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
                        print('Implement me!');
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
              // Column(
              //   children: [
              //     if (context
              //         .read<ConfigService>()
              //         .config
              //         .enableSeedPhraseLogin) ...[
              //       ArDriveButton(
              //         icon: ArDriveIcons.keypad(
              //             size: 24, color: colors.themeFgDefault),
              //         key: const Key('loginWithSeedPhraseButton'),
              //         // TODO: create/update localization key
              //         text: 'Enter Seed Phrase',
              //         onPressed: () {
              //           context.read<LoginBloc>().add(const EnterSeedPhrase());
              //         },
              //         style: ArDriveButtonStyle.secondary,
              //         fontStyle: ArDriveTypography.body.smallBold700(
              //           color: colors.themeFgDefault,
              //         ),
              //         maxWidth: double.maxFinite,
              //       ),
              //       const SizedBox(height: 16),
              //     ],
              //     ArDriveDropAreaSingleInput(
              //       controller: _dropAreaController,
              //       keepButtonVisible: true,
              //       width: double.maxFinite,
              //       // TODO: create/update localization key
              //       dragAndDropDescription: 'Select a KeyFile',
              //       dragAndDropButtonTitle: 'Select a KeyFile',
              //       errorDescription:
              //           appLocalizationsOf(context).invalidKeyFile,
              //       validateFile: (file) async {
              //         final wallet = await context
              //             .read<LoginBloc>()
              //             .validateAndReturnWalletFile(file);

              //         return wallet != null;
              //       },
              //       platformSupportsDragAndDrop: !AppPlatform.isMobile,
              //     ),
              //     const SizedBox(height: 24),
              //     GestureDetector(
              //       onTap: () {
              //         openUrl(
              //           url: Resources.howDoesKeyFileLoginWork,
              //         );
              //       },
              //       child: HoverWidget(
              //         hoverScale: 1,
              //         child: Text(
              //             appLocalizationsOf(context).howDoesKeyfileLoginWork,
              //             style: ArDriveTypography.body.smallBold().copyWith(
              //                   decoration: TextDecoration.underline,
              //                   fontSize: 14,
              //                   height: 1.5,
              //                 )),
              //       ),
              //     ),
              //     if (widget.isArConnectAvailable) ...[
              //       const SizedBox(height: 40),
              //       Row(
              //         children: [
              //           Expanded(
              //               child: Container(
              //             decoration: const ShapeDecoration(
              //               shape: RoundedRectangleBorder(
              //                 side: BorderSide(
              //                   width: 0.50,
              //                   strokeAlign: BorderSide.strokeAlignCenter,
              //                   color: Color(0xFF333333),
              //                 ),
              //               ),
              //             ),
              //           )),
              //           Padding(
              //               padding: const EdgeInsets.only(left: 25, right: 25),
              //               child: Text(
              //                 'OR',
              //                 textAlign: TextAlign.center,
              //                 style: ArDriveTypography.body
              //                     .smallBold(color: const Color(0xFF9E9E9E)),
              //               )),
              //           Expanded(
              //               child: Container(
              //             decoration: const ShapeDecoration(
              //               shape: RoundedRectangleBorder(
              //                 side: BorderSide(
              //                   width: 0.50,
              //                   strokeAlign: BorderSide.strokeAlignCenter,
              //                   color: Color(0xFF333333),
              //                 ),
              //               ),
              //             ),
              //           )),
              //         ],
              //       ),
              //       Row(
              //         children: [
              //           Expanded(
              //             child: Padding(
              //               padding: const EdgeInsets.only(top: 40),
              //               child: ArDriveButton(
              //                 icon: Padding(
              //                     padding: const EdgeInsets.only(right: 4),
              //                     child: ArDriveIcons.arconnectIcon1(
              //                       color: colors.themeFgDefault,
              //                     )),
              //                 style: ArDriveButtonStyle.secondary,
              //                 fontStyle: ArDriveTypography.body
              //                     .smallBold700(color: colors.themeFgDefault),
              //                 onPressed: () {
              //                   context
              //                       .read<LoginBloc>()
              //                       .add(const AddWalletFromArConnect());
              //                 },
              //                 // TODO: create/update localization key
              //                 text: 'Login with ArConnect',
              //               ),
              //             ),
              //           ),
              //         ],
              //       ),
              //     ],
              //     const SizedBox(
              //       height: 72,
              //     ),
              //   ],
              // ),
              // Text.rich(
              //   TextSpan(
              //     children: [
              //       TextSpan(
              //         // TODO: create/update localization key
              //         text: 'New user? Get started here!',
              //         style: ArDriveTypography.body
              //             .smallBold(
              //                 color: ArDriveTheme.of(context)
              //                     .themeData
              //                     .colors
              //                     .themeFgMuted)
              //             .copyWith(decoration: TextDecoration.underline),

              //         recognizer: TapGestureRecognizer()
              //           ..onTap = () {
              //             context
              //                 .read<LoginBloc>()
              //                 .add(const CreateNewWallet());
              //           },
              //       ),
              //     ],
              //   ),
              // ),
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
