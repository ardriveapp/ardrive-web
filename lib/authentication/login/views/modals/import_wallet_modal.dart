import 'package:ardrive/authentication/components/button.dart';
import 'package:ardrive/authentication/components/lined_text_divider.dart';
import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

void showImportWalletDialog(
    {required BuildContext context, required LoginBloc loginBloc}) {
  final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
  // FIXME: add switching of typography based on screen size
  final typography = ArDriveTypographyNew.desktop;

  final navigator = Navigator.of(context);

  showArDriveDialog(context,
      barrierDismissible: false,
      useRootNavigator: false,
      content: ArDriveLoginModal(
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
              TextField(
                decoration: InputDecoration(
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: colorTokens.strokeMid,
                    ),
                  ),
                  border: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: colorTokens.strokeMid,
                    ),
                  ),
                  hintText: 'Enter your seed phrase',
                  filled: true,
                  fillColor: colorTokens.inputDefault,
                ),
              ),
              const SizedBox(height: 20),
              ArDriveButtonNew(
                  text: 'Continue',
                  typography: typography,
                  variant: ButtonVariant.primary,
                  onPressed: () {}),
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
                    final wallet = await loginBloc
                        .validateAndReturnWalletFile(selectedFile);
                    if (wallet != null) {
                      navigator.pop();
                      loginBloc.add(AddWalletFile(selectedFile));
                    } else {
                      // TODO: Add error message
                    }
                  }),
            ],
          )));
}
