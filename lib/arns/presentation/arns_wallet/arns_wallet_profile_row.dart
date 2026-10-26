import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/arns/presentation/widgets/arns_widgets.dart';
import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The profile card's ArNS wallet row, under the wallet: the shortened
/// address, Connected or Reconnect, Change, Unlink (docs/NAMES.md, "Profile
/// card"). Nothing while names are off.
class ArNSWalletProfileRow extends StatelessWidget {
  const ArNSWalletProfileRow({super.key, this.onNavigate});

  /// Called before a dialog opens, to close the card.
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final ArNSWalletCubit cubit;
    try {
      // Checked first, so nothing is built while names are off.
      if (!context.read<ConfigService>().config.enableArNS) {
        return const SizedBox.shrink();
      }
      cubit = context.read<ArNSWalletCubit>();
    } on ProviderNotFoundException {
      return const SizedBox.shrink();
    }
    return BlocBuilder<ArNSWalletCubit, ArNSWalletState>(
      bloc: cubit,
      builder: (context, state) {
        if (state.status == ArNSWalletStatus.unavailable) {
          return const SizedBox.shrink();
        }
        final strings = appLocalizationsOf(context);
        final colors = ArDriveTheme.of(context).themeData.colorTokens;
        final typography = ArDriveTypographyNew.of(context);
        final linked = state.linked;
        final small = typography.paragraphSmall(
          color: colors.textLow,
          fontWeight: ArFontWeight.semiBold,
        );

        void openChooser({bool changing = false}) {
          onNavigate?.call();
          showArNSWalletDialog(context, changing: changing);
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(strings.arnsWallet, style: small),
              const SizedBox(height: 4),
              if (linked == null)
                ArDriveLink(
                  text: strings.arnsLinkSolanaWallet,
                  isAction: true,
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                  ),
                  onTap: openChooser,
                )
              else ...[
                Row(
                  children: [
                    ArDriveIdText(
                      shortArNSAddress(linked.address),
                      style: typography.code(
                        color: colors.textHigh,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (state.status == ArNSWalletStatus.connected)
                      _Status(
                        text: strings.arnsConnected,
                        color: colors.statusSuccessFg,
                      )
                    else if (state.status == ArNSWalletStatus.wrongAccount)
                      _Status(
                        text: strings.arnsOtherAccount,
                        color: colors.statusWarningFg,
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 12,
                  children: [
                    if (state.status != ArNSWalletStatus.connected)
                      ArDriveLink(
                        text: strings.arnsReconnect,
                        isAction: true,
                        style: typography.paragraphSmall(
                          fontWeight: ArFontWeight.semiBold,
                        ),
                        onTap: () async {
                          if (linked.walletName == null ||
                              state.noWalletInstalled) {
                            openChooser();
                            return;
                          }
                          try {
                            await cubit.reconnect();
                          } catch (e) {
                            logger.w('ArNS wallet not reconnected: $e');
                          }
                        },
                      ),
                    ArDriveLink(
                      text: strings.arnsChange,
                      isAction: true,
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      onTap: () => openChooser(changing: true),
                    ),
                    ArDriveLink(
                      text: strings.arnsUnlink,
                      isAction: true,
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                      ),
                      onTap: cubit.unlink,
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final typography = ArDriveTypographyNew.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: typography.caption(
            color: color,
            fontWeight: ArFontWeight.semiBold,
          ),
        ),
      ],
    );
  }
}
