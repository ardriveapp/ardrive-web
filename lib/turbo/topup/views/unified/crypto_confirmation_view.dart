import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
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
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        if (state is! CryptoTopupConfirmation) {
          return const Center(child: CircularProgressIndicator());
        }

        final bloc = context.read<CryptoTopupBloc>();

        return Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Red top line (ArDrive modal pattern)
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: colorTokens.containerRed,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                  ),
                ),
                // Main content
                Expanded(
                  child: Container(
                    color: colors.themeBgCanvas,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 32),
                          // Header
                          Text(
                            'Confirm Payment',
                            style: typography.heading5(
                              fontWeight: ArFontWeight.bold,
                              color: colors.themeFgDefault,
                            ),
                          ),
                          const SizedBox(height: 20),

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
                          const SizedBox(height: 16),

                          // Quote timer (less prominent)
                          _QuoteTimerBar(
                            expiresAt: state.quote.expiresAt,
                            isLoading: state.isRefreshingQuote,
                            onRefresh: () {
                              bloc.add(
                                  const CryptoTopupQuoteRefreshRequested());
                            },
                          ),

                          // Network status (for EVM tokens, only when not correct)
                          if (state.token.requiresGasEstimation &&
                              state.networkState != NetworkState.correct) ...[
                            const SizedBox(height: 12),
                            _NetworkStatusBanner(
                              networkState: state.networkState,
                              token: state.token,
                              onSwitchNetwork: () {
                                final chainId = state.token.chainId;
                                if (chainId != null) {
                                  bloc.add(CryptoTopupSwitchNetwork(chainId));
                                }
                              },
                            ),
                          ],
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                // Footer with terms and buttons
                Container(
                  color: colors.themeBgCanvas,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Divider
                      Divider(color: colors.themeBorderDefault, height: 1),
                      const SizedBox(height: 16),
                      // Terms notice
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: 'By confirming, you agree to the ',
                              style: typography.paragraphSmall(
                                color: colors.themeFgMuted,
                              ),
                            ),
                            TextSpan(
                              text: 'Terms of Service',
                              style: typography
                                  .paragraphSmall(
                                    color: colors.themeFgMuted,
                                  )
                                  .copyWith(
                                    decoration: TextDecoration.underline,
                                  ),
                              recognizer: TapGestureRecognizer()
                                ..onTap = () => openUrl(
                                      url: Resources.agreementLink,
                                    ),
                            ),
                            TextSpan(
                              text: '.',
                              style: typography.paragraphSmall(
                                color: colors.themeFgMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          if (onBack != null)
                            ArDriveClickArea(
                              child: GestureDetector(
                                onTap: onBack,
                                child: Text(
                                  'Back',
                                  style: typography.paragraphLarge(
                                    fontWeight: ArFontWeight.bold,
                                    color: colors.themeAccentDisabled,
                                  ),
                                ),
                              ),
                            )
                          else
                            const SizedBox.shrink(),
                          SizedBox(
                            height: 48,
                            child: ArDriveButton(
                              isDisabled: !state.canConfirm ||
                                  state.quote.isExpired ||
                                  state.networkState == NetworkState.checking ||
                                  state.networkState == NetworkState.switching ||
                                  state.isRefreshingQuote,
                              text: _getButtonText(state),
                              onPressed: () {
                                bloc.add(const CryptoTopupConfirmPayment());
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Close button in top right
            if (onClose != null)
              Positioned(
                right: 20,
                top: 20,
                child: ArDriveClickArea(
                  child: GestureDetector(
                    onTap: onClose,
                    child: ArDriveIcons.x(),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  String _getButtonText(CryptoTopupConfirmation state) {
    if (state.quote.isExpired) {
      return 'Quote Expired';
    }
    if (state.networkState == NetworkState.checking) {
      return 'Checking Network...';
    }
    if (state.networkState == NetworkState.switching) {
      return 'Switching Network...';
    }
    if (state.networkState == NetworkState.needsSwitch) {
      return 'Switch Network First';
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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Text(
            'PAYING WITH',
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgMuted,
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
                        color: colors.themeFgDefault,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _truncateAddress(walletAddress),
                      style: typography.paragraphSmall(
                        color: colors.themeFgMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Divider
          Divider(color: colors.themeBorderDefault, height: 1),
          const SizedBox(height: 16),

          // Amount (big and prominent)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatAmount(amount),
                    style: typography.heading4(
                      fontWeight: ArFontWeight.bold,
                      color: colors.themeFgDefault,
                    ),
                  ),
                  if (usdEquivalent != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      '~\$${NumberFormat('#,##0.00').format(usdEquivalent)}',
                      style: typography.paragraphSmall(
                        color: colors.themeFgMuted,
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                token.symbol,
                style: typography.heading4(
                  fontWeight: ArFontWeight.bold,
                  color: colors.themeFgMuted,
                ),
              ),
            ],
          ),

          // Promo/discount badge
          if (promoCode != null && promoCode!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colors.themeSuccessSubtle,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.local_offer,
                    size: 14,
                    color: colors.themeSuccessDefault,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    discountPercent != null
                        ? '$promoCode ($discountPercent% off)'
                        : promoCode!,
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colors.themeSuccessDefault,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Wallet balance (before → after)
          if (tokenBalance != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.themeBorderDefault, height: 1),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Wallet balance',
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
                  ),
                ),
                Row(
                  children: [
                    Text(
                      '${_formatAmount(tokenBalance!)} ${token.symbol}',
                      style: typography.paragraphSmall(
                        color: colors.themeFgMuted,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.arrow_forward,
                        size: 12,
                        color: colors.themeFgMuted,
                      ),
                    ),
                    Text(
                      '${_formatAmount(tokenBalanceAfter ?? 0)} ${token.symbol}',
                      style: typography.paragraphSmall(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.themeFgDefault,
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
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section label
          Text(
            "YOU'LL RECEIVE",
            style: typography.paragraphSmall(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeFgMuted,
            ),
          ),
          const SizedBox(height: 12),

          // Credits amount (big and prominent)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    convertWinstonToLiteralString(creditsToReceive),
                    style: typography.heading4(
                      fontWeight: ArFontWeight.bold,
                      color: colors.themeSuccessDefault,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    storageEstimate,
                    style: typography.paragraphSmall(
                      color: colors.themeFgMuted,
                    ),
                  ),
                ],
              ),
              Text(
                'credits',
                style: typography.heading4(
                  fontWeight: ArFontWeight.bold,
                  color: colors.themeFgMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Divider
          Divider(color: colors.themeBorderDefault, height: 1),
          const SizedBox(height: 12),

          // New balance row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'New balance',
                style: typography.paragraphSmall(
                  color: colors.themeFgMuted,
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${convertWinstonToLiteralString(newBalance)} credits',
                    style: typography.paragraphSmall(
                      fontWeight: ArFontWeight.semiBold,
                      color: colors.themeFgDefault,
                    ),
                  ),
                  Text(
                    newBalanceStorage,
                    style: typography.paragraphSmall(
                      color: colors.themeFgMuted,
                    ),
                  ),
                ],
              ),
            ],
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
        token.symbol.substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // Only show banner for non-correct states (checking, switching, needsSwitch)
    // When correct, the token name already indicates the network
    if (networkState == NetworkState.correct) {
      return const SizedBox.shrink();
    }

    if (networkState == NetworkState.checking) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.themeFgMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Checking network...',
            style: typography.paragraphSmall(
              color: colors.themeFgMuted,
            ),
          ),
        ],
      );
    }

    if (networkState == NetworkState.switching) {
      return Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.themeFgMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Switching to ${token.networkDisplayName}...',
            style: typography.paragraphSmall(
              color: colors.themeFgMuted,
            ),
          ),
        ],
      );
    }

    // Needs switch - show warning banner
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.themeWarningSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: colors.themeWarningFg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Switch to ${token.networkDisplayName}',
              style: typography.paragraphSmall(
                color: colors.themeWarningFg,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSwitchNetwork,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.themeWarningFg,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Switch',
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Quote Timer Bar
// ============================================

class _QuoteTimerBar extends StatelessWidget {
  final DateTime? expiresAt;
  final bool isLoading;
  final VoidCallback onRefresh;

  const _QuoteTimerBar({
    required this.expiresAt,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    if (expiresAt == null) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.schedule,
          size: 14,
          color: colors.themeFgMuted,
        ),
        const SizedBox(width: 6),
        StreamBuilder(
          stream: Stream.periodic(const Duration(seconds: 1)),
          builder: (context, snapshot) {
            final remaining = expiresAt!.difference(DateTime.now());
            final isExpired = remaining.isNegative;
            final minutes = remaining.inMinutes.abs();
            final seconds = (remaining.inSeconds % 60).abs();

            return Text(
              isExpired
                  ? 'Quote expired'
                  : 'Price valid for ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
              style: typography.paragraphSmall(
                color:
                    isExpired ? colors.themeErrorDefault : colors.themeFgMuted,
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: isLoading ? null : onRefresh,
          child: isLoading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.themeFgMuted,
                  ),
                )
              : Icon(
                  Icons.refresh,
                  size: 16,
                  color: colors.themeFgMuted,
                ),
        ),
      ],
    );
  }
}
