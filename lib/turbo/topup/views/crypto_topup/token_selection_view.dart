import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/pending_transaction.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Token selection view - first step in crypto topup flow.
///
/// Displays tokens with ARIO on AO as the recommended option (instant, no gas,
/// uses existing Arweave wallet), followed by other options grouped by chain.
class TokenSelectionView extends StatelessWidget {
  final VoidCallback? onClose;

  const TokenSelectionView({
    super.key,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      buildWhen: (previous, current) => current is CryptoTopupTokenSelection,
      builder: (context, state) {
        if (state is! CryptoTopupTokenSelection) {
          return const SizedBox.shrink();
        }

        return _TokenSelectionContent(
          state: state,
          onClose: onClose,
        );
      },
    );
  }
}

class _TokenSelectionContent extends StatelessWidget {
  final CryptoTopupTokenSelection state;
  final VoidCallback? onClose;

  const _TokenSelectionContent({
    required this.state,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final bloc = context.read<CryptoTopupBloc>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Select Payment Token',
                style: typography.heading4(
                  fontWeight: ArFontWeight.bold,
                  color: colorTokens.textHigh,
                ),
              ),
              if (onClose != null)
                Tooltip(
                  message: 'Close',
                  child: GestureDetector(
                    onTap: onClose,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Icon(
                        Icons.close,
                        color: colorTokens.textMid,
                        size: 24,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how you want to pay for ArDrive credits.',
            style: typography.paragraphNormal(
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 24),

          // Pending transaction banner
          if (state.pendingTransaction != null) ...[
            _PendingTransactionBanner(
              transaction: state.pendingTransaction!,
              onResume: () {
                bloc.add(const CryptoTopupResumePendingTransaction());
              },
            ),
            const SizedBox(height: 16),
          ],

          // Error banner
          if (state.error != null) ...[
            _ErrorBanner(message: state.error!),
            const SizedBox(height: 16),
          ],

          // TODO(solana-migration): Re-enable ARIO on AO recommended section once migrated to Solana
          // _RecommendedSection(
          //   arioBalance: state.arioBalance,
          //   isLoadingBalances: state.isLoadingBalances,
          //   onTokenSelected: (token) {
          //     bloc.add(CryptoTopupSelectToken(token));
          //   },
          // ),
          // const SizedBox(height: 24),

          // ===== OTHER OPTIONS SECTION =====
          _OtherOptionsSection(
            ethAddress: state.ethAddress,
            solAddress: state.solAddress,
            onTokenSelected: (token) {
              bloc.add(CryptoTopupSelectToken(token));
            },
          ),
        ],
      ),
    );
  }
}

/// Recommended section featuring ARIO on AO
// ignore: unused_element
class _RecommendedSection extends StatelessWidget {
  // ignore: unused_element
  final TokenBalance? arioBalance;
  // ignore: unused_element
  final bool isLoadingBalances;
  final ValueChanged<CryptoToken> onTokenSelected;

  const _RecommendedSection({
    this.arioBalance, // ignore: unused_element
    this.isLoadingBalances = false, // ignore: unused_element
    required this.onTokenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header with "Recommended" badge
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorTokens.containerL3,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.star,
                    size: 14,
                    color: colorTokens.textHigh,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Recommended',
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ARIO on AO card - enhanced styling
        GestureDetector(
          onTap: () => onTokenSelected(CryptoToken.arioAO),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorTokens.containerL1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: colorTokens.strokeHigh,
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Token icon placeholder
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: colorTokens.containerL2,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Center(
                        child: Text(
                          'AR',
                          style: typography.paragraphNormal(
                            fontWeight: ArFontWeight.bold,
                            color: colorTokens.textHigh,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'ARIO on AO',
                            style: typography.paragraphLarge(
                              fontWeight: ArFontWeight.bold,
                              color: colorTokens.textHigh,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Uses your connected Arweave wallet',
                            style: typography.paragraphSmall(
                              color: colorTokens.textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Balance or loading
                    if (isLoadingBalances)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorTokens.textMid,
                        ),
                      )
                    else if (arioBalance != null && !arioBalance!.hasError)
                      Text(
                        arioBalance!.displayBalance,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colorTokens.textHigh,
                        ),
                      ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: colorTokens.textMid,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Benefits row - highlight what's unique about ARIO on AO
                const Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _BenefitChip(
                      icon: Icons.bolt,
                      label: 'Instant',
                    ),
                    _BenefitChip(
                      icon: Icons.wallet,
                      label: 'No extra wallet',
                    ),
                    _BenefitChip(
                      icon: Icons.check_circle_outline,
                      label: 'Fewest steps',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Benefit chip for the recommended token
class _BenefitChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _BenefitChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: colorTokens.textMid,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
        ],
      ),
    );
  }
}

/// Other payment options section
class _OtherOptionsSection extends StatelessWidget {
  final String? ethAddress;
  final String? solAddress;
  final ValueChanged<CryptoToken> onTokenSelected;

  const _OtherOptionsSection({
    this.ethAddress,
    this.solAddress,
    required this.onTokenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Text(
          'Other Options',
          style: typography.paragraphLarge(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Connect an external wallet to pay with these tokens',
          style: typography.paragraphSmall(
            color: colorTokens.textMid,
          ),
        ),
        const SizedBox(height: 16),

        // Base Network (L2) - Primary EVM option
        _TokenGroup(
          title: 'Base Network',
          description: 'Low fees, fast transactions',
          tokens: const [
            CryptoToken.arioBase,
            CryptoToken.ethBase,
            CryptoToken.usdcBase,
          ],
          connectedAddress: ethAddress,
          onTokenSelected: onTokenSelected,
        ),
        const SizedBox(height: 16),

        // Ethereum Mainnet
        _TokenGroup(
          title: 'Ethereum',
          description: 'Higher fees, more liquidity',
          tokens: const [
            // TODO(solana-migration): Re-enable arioAOViaEth once migrated to Solana
            // CryptoToken.arioAOViaEth,
            CryptoToken.ethL1,
            CryptoToken.usdcEth,
          ],
          connectedAddress: ethAddress,
          onTokenSelected: onTokenSelected,
        ),
        const SizedBox(height: 16),

        // Solana
        _TokenGroup(
          title: 'Solana',
          description: 'Fast and low cost',
          tokens: const [CryptoToken.sol],
          connectedAddress: solAddress,
          onTokenSelected: onTokenSelected,
        ),
      ],
    );
  }
}

/// Grouped tokens by network
class _TokenGroup extends StatelessWidget {
  final String title;
  final String description;
  final List<CryptoToken> tokens;
  final String? connectedAddress;
  final ValueChanged<CryptoToken> onTokenSelected;

  const _TokenGroup({
    required this.title,
    required this.description,
    required this.tokens,
    this.connectedAddress,
    required this.onTokenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL0,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: typography.paragraphNormal(
                      fontWeight: ArFontWeight.semiBold,
                      color: colorTokens.textHigh,
                    ),
                  ),
                  Text(
                    description,
                    style: typography.paragraphSmall(
                      color: colorTokens.textLow,
                    ),
                  ),
                ],
              ),
              if (connectedAddress != null)
                _ConnectedBadge(address: connectedAddress!),
            ],
          ),
          const SizedBox(height: 12),
          // Token list - compact
          ...tokens.map((token) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _CompactTokenCard(
                token: token,
                onTap: () => onTokenSelected(token),
              ),
            );
          }),
        ],
      ),
    );
  }
}

/// Compact token card for grouped display
class _CompactTokenCard extends StatelessWidget {
  final CryptoToken token;
  final VoidCallback onTap;

  const _CompactTokenCard({
    required this.token,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colorTokens.containerL1,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Token icon
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: colorTokens.containerL2,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  token.symbol.length > 2
                      ? token.symbol.substring(0, 2)
                      : token.symbol,
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.bold,
                    color: colorTokens.textHigh,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Token name
            Expanded(
              child: Text(
                token.displayName,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
            ),
            // Arrow
            Icon(
              Icons.arrow_forward_ios,
              size: 14,
              color: colorTokens.textLow,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConnectedBadge extends StatelessWidget {
  final String address;

  const _ConnectedBadge({required this.address});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: colorTokens.textHigh,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            truncateAddress(address, prefix: 4, suffix: 4),
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingTransactionBanner extends StatelessWidget {
  final PendingCryptoTransaction transaction;
  final VoidCallback onResume;

  const _PendingTransactionBanner({
    required this.transaction,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorTokens.strokeHigh),
      ),
      child: Row(
        children: [
          Icon(
            Icons.hourglass_top,
            color: colorTokens.textMid,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pending Transaction',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colorTokens.textHigh,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You have a pending ${transaction.token.displayName} transaction',
                  style: typography.paragraphSmall(
                    color: colorTokens.textMid,
                  ),
                ),
              ],
            ),
          ),
          ArDriveButton(
            text: 'Resume',
            style: ArDriveButtonStyle.secondary,
            onPressed: onResume,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline,
            color: colorTokens.textLow,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
