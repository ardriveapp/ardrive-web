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
            _WalletOptionButton(
              name: 'Phantom',
              icon: SvgPicture.asset(
                Resources.images.login.phantom,
                fit: BoxFit.contain,
              ),
              brandColor: const Color(0xFFAB9FF2),
              onPressed: () {
                Navigator.pop(context);
                loginBloc.add(const LoginWithSolana(provider: 'phantom'));
              },
            ),
            const SizedBox(height: 12),
            _WalletOptionButton(
              name: 'Solflare',
              icon: Image.asset(
                Resources.images.login.solflare,
                fit: BoxFit.contain,
              ),
              brandColor: const Color(0xFFFC6E21),
              onPressed: () {
                Navigator.pop(context);
                loginBloc.add(const LoginWithSolana(provider: 'solflare'));
              },
            ),
            const SizedBox(height: 12),
            ArDriveButtonNew(
              text: 'Cancel',
              typography: typography,
              variant: ButtonVariant.outline,
              maxWidth: double.maxFinite,
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletOptionButton extends StatefulWidget {
  final String name;
  final Widget icon;
  final Color brandColor;
  final VoidCallback onPressed;

  const _WalletOptionButton({
    required this.name,
    required this.icon,
    required this.brandColor,
    required this.onPressed,
  });

  @override
  State<_WalletOptionButton> createState() => _WalletOptionButtonState();
}

class _WalletOptionButtonState extends State<_WalletOptionButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 56,
          decoration: BoxDecoration(
            color: _hovering
                ? widget.brandColor.withOpacity(0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovering
                  ? widget.brandColor.withOpacity(0.4)
                  : colorTokens.strokeLow,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Stack(
            children: [
              // Large brand icon bleeding off right edge
              Positioned(
                right: -12,
                top: -8,
                bottom: -8,
                child: Opacity(
                  opacity: _hovering ? 0.25 : 0.12,
                  child: SizedBox(
                    width: 72,
                    height: 72,
                    child: widget.icon,
                  ),
                ),
              ),
              // Text label
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.name,
                      style: typography.paragraphLarge(
                        color: colorTokens.textHigh,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
