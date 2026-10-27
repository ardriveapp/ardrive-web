import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Opens [url] inside a wallet's own browser, where it can connect: phones
/// only get a Solana wallet there (docs/NAMES.md, "No Solana wallet on this
/// device").
String phantomBrowseUrl(String url) =>
    'https://phantom.app/ul/browse/${Uri.encodeComponent(url)}'
    '?ref=${Uri.encodeComponent(Uri.parse(url).origin)}';

String solflareBrowseUrl(String url) =>
    'https://solflare.com/ul/v1/browse/${Uri.encodeComponent(url)}'
    '?ref=${Uri.encodeComponent(Uri.parse(url).origin)}';

/// The page a wallet's browser opens: only the app's origin on the web.
/// The address bar can hold a private drive's key, which must not reach a
/// wallet's server.
String walletBrowseTarget(Uri base, {required bool isWeb}) =>
    isWeb ? base.origin : 'https://app.ardrive.io';

const phantomDownloadUrl = 'https://phantom.com/download';
const solflareDownloadUrl = 'https://solflare.com/download';

/// The installed Solana wallets to link or reconnect, with their icons; or,
/// where none injects, "No Solana wallet found" with ways to get one.
class ArNSWalletChooser extends StatelessWidget {
  const ArNSWalletChooser({super.key, this.onLinked, this.changing = false});

  /// After a wallet connected on the linked account.
  final VoidCallback? onLinked;

  /// Choosing another ArNS wallet: whatever connects becomes the linked one.
  final bool changing;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
      builder: (context, state) {
        if (state.noWalletInstalled) return const ArNSNoWalletFound();
        final strings = appLocalizationsOf(context);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final wallet in state.installedWallets)
              _WalletRow(
                wallet: wallet,
                busy: state.connecting,
                semanticLabel: strings.arnsConnectWallet(wallet.name),
                onTap: () => _choose(context, state, wallet),
              ),
          ],
        );
      },
    );
  }

  Future<void> _choose(
    BuildContext context,
    ArNSWalletState state,
    SolanaWalletInfo wallet,
  ) async {
    final cubit = context.read<ArNSWalletCubit>();
    try {
      // With a wallet linked this reconnects it: another account connecting
      // shows as the wrong account, with Change to make it the ArNS wallet.
      if (state.linked != null && !changing) {
        await cubit.reconnect(walletName: wallet.name);
      } else {
        await cubit.link(wallet.name);
      }
      if (cubit.state.status == ArNSWalletStatus.connected) onLinked?.call();
    } catch (e) {
      // A rejected connection prompt: nothing to do but offer it again.
      logger.w('Solana wallet not connected: $e');
    }
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.wallet,
    required this.busy,
    required this.onTap,
    required this.semanticLabel,
  });

  final SolanaWalletInfo wallet;
  final bool busy;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ArDriveSpacing.xs),
      child: Semantics(
        button: true,
        label: semanticLabel,
        excludeSemantics: true,
        child: Material(
          color: colors.containerL1,
          borderRadius: BorderRadius.circular(ArDriveRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(ArDriveRadius.md),
            onTap: busy ? null : onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(
                horizontal: ArDriveSpacing.sm,
                vertical: ArDriveSpacing.xs,
              ),
              decoration: BoxDecoration(
                border: Border.all(color: colors.strokeLow),
                borderRadius: BorderRadius.circular(ArDriveRadius.md),
              ),
              child: Row(
                children: [
                  ArNSWalletIcon(icon: wallet.icon, size: 28),
                  const SizedBox(width: ArDriveSpacing.sm),
                  Expanded(
                    child: Text(
                      wallet.name,
                      style: typography.paragraphNormal(
                        color: colors.textHigh,
                        fontWeight: ArFontWeight.semiBold,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: colors.iconLow),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A wallet's Wallet Standard icon: a data URI, SVG or bitmap.
class ArNSWalletIcon extends StatelessWidget {
  const ArNSWalletIcon({super.key, required this.icon, this.size = 24});

  final String icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final fallback = Icon(
      Icons.account_balance_wallet_outlined,
      size: size,
      color: colors.iconMid,
    );
    Widget image = fallback;
    try {
      final data = UriData.parse(icon);
      final bytes = data.contentAsBytes();
      image = data.mimeType.contains('svg')
          ? SvgPicture.memory(bytes, width: size, height: size)
          : Image.memory(
              bytes,
              width: size,
              height: size,
              errorBuilder: (_, __, ___) => fallback,
            );
    } catch (_) {
      // Not a data URI: the generic wallet icon.
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(ArDriveRadius.sm),
      child: SizedBox(width: size, height: size, child: image),
    );
  }
}

/// "No Solana wallet found": common on phones, where wallets only inject
/// inside their own app browsers. Names stay readable from the remembered
/// address.
class ArNSNoWalletFound extends StatelessWidget {
  const ArNSNoWalletFound({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = appLocalizationsOf(context);
    final here = walletBrowseTarget(Uri.base, isWeb: kIsWeb);
    return ArDriveNotice(
      type: ArDriveNoticeType.info,
      title: strings.arnsNoWalletFound,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            strings.arnsNoWalletFoundBody,
            style: ArDriveTypographyNew.of(context).paragraphNormal(
              color: ArDriveTheme.of(context).themeData.colorTokens.textHigh,
            ),
          ),
          const SizedBox(height: ArDriveSpacing.xs),
          Wrap(
            spacing: ArDriveSpacing.md,
            runSpacing: ArDriveSpacing.xxs,
            children: [
              ArDriveLink(
                text: strings.arnsOpenInPhantom,
                external: true,
                onTap: () => openUrl(url: phantomBrowseUrl(here)),
              ),
              ArDriveLink(
                text: strings.arnsOpenInSolflare,
                external: true,
                onTap: () => openUrl(url: solflareBrowseUrl(here)),
              ),
              ArDriveLink(
                text: strings.arnsGetAWallet,
                external: true,
                onTap: () => openUrl(url: phantomDownloadUrl),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
