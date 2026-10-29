import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/quote_timer.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';

/// Streamlined crypto payment confirmation view.
///
/// Two-section layout focused on clarity:
/// 1. "Paying With" - what you're spending
/// 2. "You'll Receive" - what you're getting
class CryptoConfirmationView extends StatelessWidget {
  final VoidCallback? onBack;
  final VoidCallback? onClose;

  const CryptoConfirmationView({
    super.key,
    this.onBack,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final onBack = this.onBack;

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        if (state is! CryptoTopupConfirmation) {
          return TurboTopupScaffold(
            title: 'Confirm payment',
            onClose: onClose,
            canClose: onClose != null,
            child: const SizedBox(
              height: 200,
              child: Center(
                child: ArDriveSpinner(size: ArDriveSpinnerSize.large),
              ),
            ),
          );
        }

        final bloc = context.read<CryptoTopupBloc>();

        return TurboTopupScaffold(
          title: 'Confirm payment',
          onClose: onClose,
          canClose: onClose != null,
          actions: [
            if (onBack != null)
              ModalAction.dismiss(title: 'Back', action: onBack),
            ModalAction(
              title: _getButtonText(state),
              isEnable: state.canConfirm &&
                  !state.quote.isExpired &&
                  state.networkState != NetworkState.checking &&
                  state.networkState != NetworkState.switching &&
                  !state.isRefreshingQuote,
              action: () => bloc.add(const CryptoTopupConfirmPayment()),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: QuoteTimer(
                  expiresAt: state.quote.expiresAt,
                  isLoading: state.isRefreshingQuote,
                  onRefresh: () {
                    bloc.add(const CryptoTopupQuoteRefreshRequested());
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Section 1: Paying With
              _PayingWithSection(
                token: state.token,
                walletAddress: state.fromAddress,
                amount: state.quote.tokenAmountDisplay,
                usdEquivalent: state.quote.usdValue,
                promoCode: state.promoCode,
                discountPercent: state.quote.hasDiscount
                    ? state.quote.discountPercentage.round()
                    : null,
                tokenBalance: state.tokenBalance,
                tokenBalanceAfter: state.tokenBalanceAfter,
              ),
              const SizedBox(height: 16),

              // Section 2: You'll Receive
              _YoullReceiveSection(
                creditsToReceive: state.quote.wincAmount,
                storageEstimate: state.quote.formattedStorage,
                newBalance: state.newTurboBalance,
                newBalanceStorage: state.newBalanceStorage,
              ),

              // Network status (for EVM tokens, only when not correct)
              if (state.token.requiresGasEstimation &&
                  state.networkState != NetworkState.correct) ...[
                const SizedBox(height: 16),
                _NetworkStatusBanner(
                  networkState: state.networkState,
                  token: state.token,
                  onSwitchNetwork: () {
                    final chainId =
                        bloc.networkConfig.getChainIdForToken(state.token);
                    if (chainId != null) {
                      bloc.add(CryptoTopupSwitchNetwork(chainId));
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),

              // Terms notice
              Text.rich(
                TextSpan(
                  style: typography.paragraphSmall(color: colors.textMid),
                  children: [
                    const TextSpan(text: 'By continuing, you agree to the '),
                    ArDriveLink.span(
                      text: 'Terms of Service',
                      style: typography.paragraphSmall(),
                      color: colors.textMid,
                      external: true,
                      onTap: () => openUrl(url: Resources.agreementLink),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getButtonText(CryptoTopupConfirmation state) {
    if (state.quote.isExpired) {
      return 'Quote expired';
    }
    if (state.networkState == NetworkState.checking) {
      return 'Checking Network...';
    }
    if (state.networkState == NetworkState.switching) {
      return 'Switching Network...';
    }
    if (state.networkState == NetworkState.needsSwitch) {
      return 'Switch network first';
    }
    if (state.hasInsufficientBalance) {
      return 'Not enough ${state.token.symbol}';
    }
    return 'Confirm & Pay';
  }
}

// ============================================
// Section 1: Paying With
// ============================================

class _PayingWithSection extends StatelessWidget {
  final CryptoToken token;
  final String walletAddress;
  final double amount;
  final double? usdEquivalent;
  final String? promoCode;
  final int? discountPercent;
  final double? tokenBalance;
  final double? tokenBalanceAfter;

  const _PayingWithSection({
    required this.token,
    required this.walletAddress,
    required this.amount,
    this.usdEquivalent,
    this.promoCode,
    this.discountPercent,
    this.tokenBalance,
    this.tokenBalanceAfter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Text(
            'PAYING WITH',
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colors.textMid,
            ),
          ),
          const SizedBox(height: 12),

          // Token info row
          Row(
            children: [
              // Token icon
              _TokenIcon(token: token, size: 40),
              const SizedBox(width: 12),
              // Token name and wallet
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      token.displayName,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _truncateAddress(walletAddress),
                      style: typography.code(color: colors.textMid),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Divider
          Divider(color: colors.strokeMid, height: 1),
          const SizedBox(height: 16),

          // Amount (big and prominent)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The amount paid is this card's figure.
              // One text, so the unit wraps under the figure rather than
              // overflowing a narrow column.
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                        text: _formatAmount(amount),
                        style: typography.heading2(
                          color: colors.textHigh,
                          fontWeight: ArFontWeight.light,
                        )),
                    const TextSpan(text: ' '),
                    TextSpan(
                        text: token.symbol,
                        style: typography.paragraphNormal(
                          fontWeight: ArFontWeight.semiBold,
                          color: colors.textMid,
                        )),
                  ],
                ),
              ),
              if (usdEquivalent != null) ...[
                const SizedBox(height: 2),
                Text(
                  '~\$${NumberFormat('#,##0.00').format(usdEquivalent)}',
                  style: typography.paragraphSmall(
                    color: colors.textMid,
                  ),
                ),
              ],
            ],
          ),

          // Promo/discount badge
          if (promoCode != null && promoCode!.isNotEmpty) ...[
            const SizedBox(height: 12),
            ArDriveTag(
              type: ArDriveTagType.success,
              icon: Icons.local_offer,
              text: discountPercent != null
                  ? '$promoCode ($discountPercent% off)'
                  : promoCode!,
            ),
          ],

          // Wallet balance (before → after)
          if (tokenBalance != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.strokeMid, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Wallet balance',
                  style: typography.paragraphSmall(
                    color: colors.textMid,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${_formatAmount(tokenBalance!)} ${token.symbol}',
                      style: typography.paragraphSmall(
                        color: colors.textMid,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 12,
                        color: colors.textMid,
                      ),
                    ),
                    Text(
                      '${_formatAmount(tokenBalanceAfter ?? 0)} ${token.symbol}',
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.textHigh,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble() && amount < 1000) {
      return amount.toInt().toString();
    }
    return amount
        .toStringAsFixed(4)
        .replaceAll(RegExp(r'0+$'), '')
        .replaceAll(RegExp(r'\.$'), '');
  }

  String _truncateAddress(String address) {
    if (address.length <= 12) return address;
    return shortenId(address);
  }
}

// ============================================
// Section 2: You'll Receive
// ============================================

class _YoullReceiveSection extends StatelessWidget {
  final BigInt creditsToReceive;
  final String storageEstimate;
  final BigInt newBalance;
  final String newBalanceStorage;

  const _YoullReceiveSection({
    required this.creditsToReceive,
    required this.storageEstimate,
    required this.newBalance,
    required this.newBalanceStorage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.strokeMid),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Credits to receive (left side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "YOU'LL RECEIVE",
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textMid,
                  ),
                ),
                const SizedBox(height: 4),
                // The credits bought are this card's figure.
                // One text, so the unit wraps under the figure rather than
                // overflowing a narrow column.
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                          text: convertWinstonToLiteralString(creditsToReceive),
                          style: typography.heading2(
                            color: colors.textHigh,
                            fontWeight: ArFontWeight.light,
                          )),
                      const TextSpan(text: ' '),
                      TextSpan(
                          text: 'credits',
                          style: typography.paragraphSmall(
                            fontWeight: ArFontWeight.semiBold,
                            color: colors.textMid,
                          )),
                    ],
                  ),
                ),
                Text(
                  storageEstimate,
                  style: typography.paragraphSmall(
                    color: colors.textMid,
                  ),
                ),
              ],
            ),
          ),
          // Vertical divider
          Container(
            width: 1,
            height: 50,
            color: colors.strokeMid,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          // New balance (right side)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NEW BALANCE',
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textMid,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${convertWinstonToLiteralString(newBalance)} credits',
                  style: typography.paragraphNormal(
                    fontWeight: ArFontWeight.semiBold,
                    color: colors.textHigh,
                  ),
                ),
                Text(
                  newBalanceStorage,
                  style: typography.paragraphSmall(
                    color: colors.textMid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Token Icon
// ============================================

class _TokenIcon extends StatelessWidget {
  final CryptoToken token;
  final double size;

  const _TokenIcon({
    required this.token,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final isSvg = token.logoAsset.endsWith('.svg');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getTokenColor(token),
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: isSvg
            ? SvgPicture.asset(
                token.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholderBuilder: (context) => _buildFallback(),
              )
            : Image.asset(
                token.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _buildFallback(),
              ),
      ),
    );
  }

  Widget _buildFallback() {
    return Center(
      child: Text(
        token.symbol
            .substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
          // On the token's brand colour, below.
          color: Colors.white,
        ),
      ),
    );
  }

  // The tokens' own brand colours, not ArDrive's.
  Color _getTokenColor(CryptoToken token) {
    return switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth ||
      CryptoToken.arioBase =>
        const Color(0xFF000000),
      CryptoToken.ethL1 || CryptoToken.ethBase => const Color(0xFF627EEA),
      CryptoToken.sol => const Color(0xFF9945FF),
      CryptoToken.usdcBase || CryptoToken.usdcEth => const Color(0xFF2775CA),
    };
  }
}

// ============================================
// Network Status Banner
// ============================================

class _NetworkStatusBanner extends StatelessWidget {
  final NetworkState networkState;
  final CryptoToken token;
  final VoidCallback onSwitchNetwork;

  const _NetworkStatusBanner({
    required this.networkState,
    required this.token,
    required this.onSwitchNetwork,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // Only show banner for non-correct states (checking, switching, needsSwitch)
    // When correct, the token name already indicates the network
    if (networkState == NetworkState.correct) {
      return const SizedBox.shrink();
    }

    if (networkState == NetworkState.checking) {
      return Row(
        children: [
          ArDriveSpinner(color: colors.textMid),
          const SizedBox(width: 6),
          Text(
            'Checking network...',
            style: typography.paragraphSmall(
              color: colors.textMid,
            ),
          ),
        ],
      );
    }

    if (networkState == NetworkState.switching) {
      return Row(
        children: [
          ArDriveSpinner(color: colors.textMid),
          const SizedBox(width: 6),
          Text(
            'Switching to ${token.networkDisplayName}...',
            style: typography.paragraphSmall(
              color: colors.textMid,
            ),
          ),
        ],
      );
    }

    // Needs switch - show warning banner
    return ArDriveNotice(
      type: ArDriveNoticeType.warning,
      message: 'Switch to ${token.networkDisplayName}',
      actionLabel: 'Switch',
      onAction: onSwitchNetwork,
    );
  }
}
