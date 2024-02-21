import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/login_card_new.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/io_utils.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WalletCreatedView extends StatefulWidget {
  const WalletCreatedView(
      {Key? key, required this.mnemonic, required this.wallet})
      : super(key: key);

  final String mnemonic;
  final Wallet wallet;

  @override
  State<WalletCreatedView> createState() => _WalletCreatedViewState();
}

class _WalletCreatedViewState extends State<WalletCreatedView> {
  bool _isTermsChecked = false;

  @override
  void initState() {
    super.initState();

    PlausibleEventTracker.trackPageview(
        page: PlausiblePageView.walletGenerationPage);
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.desktop;

    return Material(
        child: Container(
      color: colorTokens.containerL0,
      alignment: Alignment.center,
      child: Center(
          child: IntrinsicHeight(
              child: Row(
        mainAxisSize: MainAxisSize.max,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LoginCardNew(
            child: Text('Mnemonic: ${widget.mnemonic}'),
          ),
          const SizedBox(width: 24),
          LoginCardNew(
              child: Padding(
            padding: const EdgeInsets.fromLTRB(56, 64, 56, 64),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                    child: ArDriveImage(
                  image: AssetImage(Resources.images.login.checkCircle),
                  height: 32,
                )),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    // FIXME: Add localization key
                    'Wallet Created',
                    style: typography.heading2(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.bold),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Please download your key file to continue. If you log out, you will need this to log back in.',
                  style: ArDriveTypographyNew.desktop.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 40),
                ArDriveButtonNew(
                  typography: typography,
                  text: 'Copy Seed Phrase',
                  variant: ButtonVariant.outline,
                  onPressed: () async {
                    Clipboard.setData(ClipboardData(text: widget.mnemonic));
                  },
                ),
                const SizedBox(height: 12),
                ArDriveButtonNew(
                  typography: typography,
                  text: 'Download Keyfile',
                  variant: ButtonVariant.outline,
                  onPressed: () async {
                    final ioUtils = ArDriveIOUtils();

                    await ioUtils.downloadWalletAsJsonFile(
                      wallet: widget.wallet,
                    );
                  },
                ),
                const SizedBox(height: 40),
                ArDriveButtonNew(
                  typography: typography,
                  text: _isTermsChecked ? 'Go to App' : 'Check to Continue',
                  isDisabled: !_isTermsChecked,
                  variant: ButtonVariant.primary,
                  onPressed: () async {
                    context.read<LoginBloc>().add(
                          FinishOnboarding(
                            wallet: widget.wallet,
                          ),
                        );
                  },
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Checkbox(
                    fillColor: MaterialStateProperty.all(Colors.transparent),
                    checkColor: colorTokens.textLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2.0),
                    ),
                    side: MaterialStateBorderSide.resolveWith((states) =>
                        BorderSide(width: 1.0, color: colorTokens.textLow)),
                    value: _isTermsChecked,
                    onChanged: ((value) {
                      setState(() => _isTermsChecked = value ?? false);
                    }),
                  ),
                  Text('I have safely backed-up a copy of my wallet.',
                      style: typography.paragraphNormal(
                          color: colorTokens.textLow,
                          fontWeight: ArFontWeight.semiBold))
                ]),
              ],
            ),
          )),
        ],
      ))),
    ));
  }
}
