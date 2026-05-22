import 'package:ardrive/authentication/components/login_modal.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class SolanaWalletPickerModal extends StatelessWidget {
  const SolanaWalletPickerModal({super.key, required this.loginBloc});

  final LoginBloc loginBloc;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return SingleChildScrollView(
      child: ArDriveLoginModal(
        width: 380,
        hasCloseButton: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Image.asset(
                Resources.images.login.solana,
                height: 36,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.topCenter,
              child: Text(
                'Select Wallet',
                style: typography.heading2(
                  color: colorTokens.textHigh,
                  fontWeight: ArFontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which Solana wallet to connect.',
              style: typography.paragraphNormal(
                color: colorTokens.textLow,
                fontWeight: ArFontWeight.semiBold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ArDriveButtonNew(
              text: 'Phantom',
              hoverIcon: Container(
                alignment: Alignment.center,
                child: SvgPicture.asset(
                  Resources.images.login.phantom,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
              typography: typography,
              maxWidth: double.maxFinite,
              onPressed: () {
                Navigator.pop(context);
                loginBloc.add(const LoginWithSolana(provider: 'phantom'));
              },
            ),
            const SizedBox(height: 12),
            ArDriveButtonNew(
              text: 'Solflare',
              hoverIcon: Container(
                alignment: Alignment.center,
                child: Image.asset(
                  Resources.images.login.solflare,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                ),
              ),
              typography: typography,
              maxWidth: double.maxFinite,
              onPressed: () {
                Navigator.pop(context);
                loginBloc.add(const LoginWithSolana(provider: 'solflare'));
              },
            ),
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: typography.paragraphNormal(
                    color: colorTokens.textLow,
                    fontWeight: ArFontWeight.semiBold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showSolanaWalletPickerDialog({
  required BuildContext context,
  required LoginBloc loginBloc,
}) {
  showArDriveDialog(
    context,
    barrierDismissible: true,
    useRootNavigator: false,
    content: SolanaWalletPickerModal(loginBloc: loginBloc),
  );
}
