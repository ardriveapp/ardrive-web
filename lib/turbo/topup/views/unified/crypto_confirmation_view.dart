import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/purchase_summary.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Streamlined crypto payment confirmation view.
///
/// Shows a summary of the payment and a confirm button.
/// This replaces the previous multi-step confirmation flow.
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
                          const SizedBox(height: 32), // Space for close button
                          // Header
                          Text(
                            'Confirm Payment',
                            style: typography.heading5(
                              fontWeight: ArFontWeight.bold,
                              color: colors.themeFgDefault,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Quote timer bar (styled like credit card review)
                          _QuoteTimerBar(
                            expiresAt: state.quote.expiresAt,
                            isLoading: false,
                            onRefresh: () {
                              bloc.add(
                                  const CryptoTopupQuoteRefreshRequested());
                            },
                          ),
                          const SizedBox(height: 16),

                          // Comprehensive checkout summary
                          CheckoutSummary(
                            creditsToReceive: state.quote.wincAmount,
                            storageEstimate: state.quote.formattedStorage,
                            priceAmount: state.quote.tokenAmountDisplay,
                            priceSymbol: state.token.symbol,
                            isPriceInToken: true,
                            usdEquivalent: state.quote.usdValue,
                            currentBalance: state.currentTurboBalance,
                            currentBalanceStorage: state.currentBalanceStorage,
                            newBalanceStorage: state.newBalanceStorage,
                            tokenSymbol: state.token.symbol,
                            tokenBalance: state.tokenBalance,
                            tokenBalanceAfter: state.tokenBalanceAfter,
                            // Network fee is shown by the wallet itself, not needed here
                            promoCode: state.promoCode,
                            discountPercent: state.quote.hasDiscount
                                ? state.quote.discountPercentage.round()
                                : null,
                          ),
                          const SizedBox(height: 16),

                          // Network status (for EVM tokens)
                          if (state.token.requiresGasEstimation) ...[
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
                            const SizedBox(height: 16),
                          ],

                          // Terms notice with link
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
                                  text: 'Terms of Service and Privacy Policy',
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
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                ),
                // Footer with back button on left and confirm button on right
                Container(
                  color: colors.themeBgCanvas,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Row(
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
                              state.networkState == NetworkState.checking,
                          text: _getButtonText(state),
                          onPressed: () {
                            bloc.add(const CryptoTopupConfirmPayment());
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Close button in top right
            if (onClose != null)
              Positioned(
                right: 27,
                top: 27,
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
      return 'Quote Expired - Go Back';
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
    return 'Confirm & Pay ${state.quote.formattedTokenAmount}';
  }
}

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

    if (networkState == NetworkState.checking) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.themeFgMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Checking network...',
              style: typography.paragraphSmall(
                color: colors.themeFgMuted,
              ),
            ),
          ],
        ),
      );
    }

    if (networkState == NetworkState.correct) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.themeBorderDefault),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: colors.themeFgMuted, size: 20),
            const SizedBox(width: 8),
            Text(
              'Connected to ${token.networkDisplayName}',
              style: typography.paragraphSmall(
                color: colors.themeFgDefault,
              ),
            ),
          ],
        ),
      );
    }

    if (networkState == NetworkState.switching) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.themeBgSubtle,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.themeFgMuted,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Switching network...',
              style: typography.paragraphSmall(
                color: colors.themeFgMuted,
              ),
            ),
          ],
        ),
      );
    }

    // Needs switch
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.themeWarningSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: colors.themeWarningFg, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Please switch to ${token.networkDisplayName}',
              style: typography.paragraphSmall(
                color: colors.themeWarningFg,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onSwitchNetwork,
            child: Text(
              'Switch',
              style: typography.paragraphSmall(
                fontWeight: ArFontWeight.bold,
                color: colors.themeWarningFg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Styled quote timer bar with refresh button (matches credit card review)
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Row(
        children: [
          Icon(
            Icons.schedule,
            size: 16,
            color: colors.themeFgMuted,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: StreamBuilder(
              stream: Stream.periodic(const Duration(seconds: 1)),
              builder: (context, snapshot) {
                final remaining = expiresAt!.difference(DateTime.now());
                final isExpired = remaining.isNegative;
                final minutes = remaining.inMinutes.abs();
                final seconds = (remaining.inSeconds % 60).abs();

                return Text(
                  isExpired
                      ? 'Quote expired'
                      : 'Quote updates in ${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                  style: typography.paragraphSmall(
                    color: isExpired
                        ? colors.themeErrorDefault
                        : colors.themeFgMuted,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          ArDriveClickArea(
            child: GestureDetector(
              onTap: isLoading ? null : onRefresh,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.themeBgCanvas,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: colors.themeBorderDefault),
                ),
                child: isLoading
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.themeFgMuted,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh,
                            size: 14,
                            color: colors.themeFgMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Refresh',
                            style: typography.paragraphSmall(
                              fontWeight: ArFontWeight.semiBold,
                              color: colors.themeFgDefault,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
