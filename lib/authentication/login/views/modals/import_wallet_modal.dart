import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/lined_text_divider.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/authentication/login/views/modals/common.dart';
import 'package:ardrive/authentication/login/views/modals/loader_modal.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:flutter/material.dart';

import '../../blocs/stub_web_wallet.dart' // stub implementation
    if (dart.library.html) '../../blocs/web_wallet.dart';

class ImportWalletModal extends StatefulWidget {
  const ImportWalletModal({Key? key, required this.loginBloc})
      : super(key: key);

  final LoginBloc loginBloc;

  @override
  State<ImportWalletModal> createState() => _ImportWalletModalState();
}

class _ImportWalletModalState extends State<ImportWalletModal> {
  final _seedPhraseController = ArDriveMultilineObscureTextControllerNew();

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.desktop;

    final navigator = Navigator.of(context);

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
                // FIXME: Add localization key
                'Import Wallet',
                style: typography.heading2(
                    color: colorTokens.textHigh, fontWeight: ArFontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Text(
                'You can import your wallet by entering an existing seed phrase or uploading a keyfile.',
                style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold)),
            const SizedBox(height: 40),
            Text('Seed Phrase',
                style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold)),
            const SizedBox(height: 8),
            ArDriveTextFieldNew(
              autofocus: true,
              controller: _seedPhraseController,
              showObfuscationToggle: true,
              obscureText: true,
              // TODO: create/update localization key
              hintText: 'Enter Seed Phrase',
              textInputAction: TextInputAction.next,
              minLines: 3,
              maxLines: 3,
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
                text: 'Upload Keyfile',
                typography: typography,
                variant: ButtonVariant.outline,
                onPressed: () async {
                  final selectedFile = await ArDriveIO()
                      .pickFile(fileSource: FileSource.fileSystem);
                  final wallet = await widget.loginBloc
                      .validateAndReturnWalletFile(selectedFile);
                  if (wallet != null) {
                    navigator.pop();
                    widget.loginBloc.add(AddWalletFile(selectedFile));
                  } else {
                    // TODO: Add error message
                  }
                }),
          ],
        ));
  }

  void _onSubmitSeedPhrase() async {
    final isValid = _seedPhraseController.text.isNotEmpty &&
        bip39.validateMnemonic(_seedPhraseController.text);

    if (!isValid) {
      showErrorDialog(
          context: context,
          message:
              'The seed phrase you have provided is invalid. Please correct and retry.');
      return;
    }

    // Navigator.pop(context);
    showLoaderDialog(context: context, loginBloc: widget.loginBloc);
    final wallet = await generateWalletFromMnemonic(_seedPhraseController.text);
    // FIXME: Trying to pop the current dialog before showLoaderDialog()
    // and then trying to pop the loader dialog caused problems with context
    // Revise this code for better UX

    // ignore: use_build_context_synchronously
    Navigator.pop(context);
    // ignore: use_build_context_synchronously
    Navigator.pop(context);

    widget.loginBloc
        .add(AddWalletFromSeedPhraseLogin(_seedPhraseController.text, wallet));
  }
}

void showImportWalletDialog(
    {required BuildContext context, required LoginBloc loginBloc}) {
  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: ImportWalletModal(loginBloc: loginBloc));
}
