import 'package:ardrive/authentication/components/login_card.dart';
import 'package:ardrive/authentication/login/blocs/login_bloc.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';

/// The sign-in panel while a browser wallet is asked to connect or sign:
/// where to approve it, and Cancel, which always works, even when the
/// extension never answers.
class WalletWaitView extends StatelessWidget {
  const WalletWaitView({
    super.key,
    required this.wallet,
    required this.request,
  });

  final BrowserWallet wallet;
  final BrowserWalletRequest request;

  /// The wallet's own name, which isn't translated. Null for a Solana
  /// wallet other than Phantom or Solflare.
  static String? nameOf(BrowserWallet wallet) => switch (wallet) {
        BrowserWallet.wander => 'Wander',
        BrowserWallet.metamask => 'MetaMask',
        BrowserWallet.phantom => 'Phantom',
        BrowserWallet.solflare => 'Solflare',
        BrowserWallet.otherSolana => null,
      };

  Widget _logo() {
    const size = 64.0;
    final login = Resources.images.login;
    return switch (wallet) {
      BrowserWallet.wander =>
        SvgPicture.asset(login.wanderLogo, width: size, height: size),
      BrowserWallet.metamask =>
        SvgPicture.asset(login.metamask, width: size, height: size),
      BrowserWallet.phantom =>
        SvgPicture.asset(login.phantom, width: size, height: size),
      BrowserWallet.solflare =>
        Image.asset(login.solflare, width: size, height: size),
      BrowserWallet.otherSolana =>
        Image.asset(login.solana, width: size, height: size),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = appLocalizationsOf(context);
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final type = ArDriveTypographyNew.of(context);
    final name = nameOf(wallet);
    final title =
        name == null ? s.walletWaitTitleGeneric : s.walletWaitTitle(name);
    final body = switch ((name, request)) {
      (null, BrowserWalletRequest.connect) => s.walletWaitConnectGeneric,
      (null, BrowserWalletRequest.signIn) => s.walletWaitSignInGeneric,
      (null, BrowserWalletRequest.openDrives) => s.approveToOpenDrivesGeneric,
      (final String n, BrowserWalletRequest.connect) => s.walletWaitConnect(n),
      (final String n, BrowserWalletRequest.signIn) => s.walletWaitSignIn(n),
      (final String n, BrowserWalletRequest.openDrives) =>
        s.approveToOpenDrives(n),
    };
    final progress =
        name == null ? s.walletWaitProgressGeneric : s.walletWaitProgress(name);

    return SizedBox(
      width: 381,
      child: LoginCard(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(child: Center(child: _logo())),
            const SizedBox(height: ArDriveSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: type.heading2(
                color: colors.textHigh,
                fontWeight: ArFontWeight.bold,
              ),
            ),
            const SizedBox(height: ArDriveSpacing.xs),
            Text(
              body,
              key: const Key('walletWaitBody'),
              textAlign: TextAlign.center,
              style: type.paragraphNormal(color: colors.textMid),
            ),
            const SizedBox(height: ArDriveSpacing.lg),
            ArDriveLinearProgress(semanticsLabel: progress),
            const SizedBox(height: ArDriveSpacing.lg),
            Center(
              child: ArDriveLink(
                key: const Key('walletWaitCancel'),
                text: s.cancel,
                isAction: true,
                onTap: () =>
                    context.read<LoginBloc>().add(const CancelWalletLogin()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
