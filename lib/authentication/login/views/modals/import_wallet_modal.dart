import 'package:ardrive/authentication/components/lined_text_divider.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ImportWalletModal extends StatefulWidget {
  const ImportWalletModal({super.key, required this.loginBloc});

  final LoginBloc loginBloc;

  @override
  State<ImportWalletModal> createState() => _ImportWalletModalState();
}

class _ImportWalletModalState extends State<ImportWalletModal> {
  final _seedPhraseController = ArDriveMultilineObscureTextControllerNew();
  bool showSeedPhraseError = false;

  @override
  initState() {
    super.initState();
    PlausibleEventTracker.trackPageview(
      page: PlausiblePageView.importWalletPage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final navigator = Navigator.of(context);

    return SingleChildScrollView(
      child: ArDriveLoginModal(
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
                  // FIXME: Add localization key
                  'Import Wallet',
                  style: typography.heading2(
                      color: colorTokens.textHigh,
                      fontWeight: ArFontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'You can import your wallet by entering an existing seed phrase or keyfile.',
                style: typography.paragraphNormal(
                  color: colorTokens.textLow,
                  fontWeight: ArFontWeight.semiBold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              Text('Seed Phrase',
                  style: typography.paragraphNormal(
                      color: colorTokens.textLow,
                      fontWeight: ArFontWeight.semiBold)),
              const SizedBox(height: 8),
              ArDriveTextFieldNew(
                key: const Key('import_wallet_modal_seed_phrase_text_field'),
                autofocus: true,
                controller: _seedPhraseController,
                showObfuscationToggle: true,
                obscureText: true,
                // TODO: create/update localization key
                hintText: 'Enter Seed Phrase',
                textInputAction: TextInputAction.next,
                minLines: 3,
                maxLines: 3,
                errorMessage: 'The seed phrase provided is invalid.',
                showErrorMessage: showSeedPhraseError,
                onChanged: (value) {
                  setState(() {
                    showSeedPhraseError = false;
                  });
                },
              ),
              const SizedBox(height: 20),
              ArDriveButtonNew(
                  text: 'Continue',
                  typography: typography,
                  variant: ButtonVariant.primary,
                  onPressed: _onSubmitSeedPhrase),
              const SizedBox(height: 40),
              const LinedTextDivider(),
              const SizedBox(height: 40),
              ArDriveButtonNew(
                  text: 'Use Keyfile',
                  typography: typography,
                  variant: ButtonVariant.outline,
                  onPressed: () async {
                    final selectedFile = await context
                        .read<ArDriveIO>()
                        .pickFile(fileSource: FileSource.fileSystem);
                    logger.d('selectedFile: $selectedFile');

                    final wallet = await widget.loginBloc
                        .validateAndReturnWalletFile(selectedFile);
                    logger.d('wallet: $wallet');
                    if (wallet != null) {
                      navigator.pop();
                      PlausibleEventTracker.trackClickUseKeyfileButton();
                      widget.loginBloc.add(AddWalletFile(selectedFile));
                    } else {
                      // TODO: Add error message
                    }
                  }),
            ],
          )),
    );
  }

  void _onSubmitSeedPhrase() async {
    final isValid = _seedPhraseController.text.isNotEmpty &&
        bip39.validateMnemonic(_seedPhraseController.text);

    if (!isValid) {
      setState(() {
        showSeedPhraseError = true;
      });
      return;
    }
    PlausibleEventTracker.trackClickContinueWithSeedphraseButton();
    Navigator.pop(context);
    widget.loginBloc
        .add(AddWalletFromSeedPhraseLogin(_seedPhraseController.text));
  }
}

void showImportWalletDialog(
    {required BuildContext context, required LoginBloc loginBloc}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: ImportWalletModal(loginBloc: loginBloc));
}
