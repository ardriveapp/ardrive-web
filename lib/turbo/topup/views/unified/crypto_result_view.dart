import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Success view shown after successful crypto payment.
class CryptoSuccessView extends StatelessWidget {
  final VoidCallback? onDone;

  const CryptoSuccessView({
    super.key,
    this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        if (state is! CryptoTopupSuccess) {
          return const SizedBox.shrink();
        }

        final token = state.token;
        final txId = state.txId;

        return Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Container(
                  color: colors.themeBgCanvas,
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title - left aligned with icon
                      Row(
                        children: [
                          ArDriveIcons.checkCirle(
                            size: 28,
                            color: colors.themeSuccessDefault,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Payment Successful',
                            style: typography.heading5(
                              fontWeight: ArFontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Summary card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.themeBgSubtle,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            // Amount paid
                            _SummaryRow(
                              label: 'Paid',
                              value: _formatTokenAmount(
                                  state.tokenAmountSpent, token.symbol),
                              subValue: state.usdValue != null
                                  ? '\$${state.usdValue!.toStringAsFixed(2)}'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            Divider(
                                color: colors.themeBorderDefault, height: 1),
                            const SizedBox(height: 12),
                            // Credits added
                            _SummaryRow(
                              label: 'Credits added',
                              value: _formatCredits(state.creditsAdded),
                            ),
                            // New balance (if available)
                            if (state.newBalance != null) ...[
                              const SizedBox(height: 12),
                              Divider(
                                  color: colors.themeBorderDefault, height: 1),
                              const SizedBox(height: 12),
                              _SummaryRow(
                                label: 'New balance',
                                value: _formatCredits(state.newBalance!),
                                isHighlighted: true,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Transaction ID as clickable link
                      if (txId.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        GestureDetector(
                          onTap: () async {
                            final url = Uri.parse(token.getExplorerUrl(txId));
                            if (await canLaunchUrl(url)) {
                              await launchUrl(url,
                                  mode: LaunchMode.externalApplication);
                            }
                          },
                          child: Row(
                            children: [
                              Text(
                                'Transaction: ',
                                style: typography.paragraphSmall(
                                  color: colors.themeFgMuted,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  _truncateTxId(txId),
                                  style: typography.paragraphSmall(
                                    fontWeight: ArFontWeight.semiBold,
                                    color: colors.themeAccentDefault,
                                  ),
                                ),
                              ),
                              ArDriveIcons.newWindow(
                                size: 14,
                                color: colors.themeAccentDefault,
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),
                      // Done button - right aligned
                      Align(
                        alignment: Alignment.centerRight,
                        child: ArDriveButton(
                          maxHeight: 44,
                          maxWidth: 143,
                          text: 'Done',
                          fontStyle: typography.paragraphLarge(
                            fontWeight: ArFontWeight.bold,
                            color: Colors.white,
                          ),
                          onPressed: onDone,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Close button in top right
            Positioned(
              right: 20,
              top: 20,
              child: ArDriveClickArea(
                child: GestureDetector(
                  onTap: onDone,
                  child: ArDriveIcons.x(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTokenAmount(double amount, String symbol) {
    if (amount >= 1000) {
      return '${amount.toStringAsFixed(0)} $symbol';
    } else if (amount >= 1) {
      return '${amount.toStringAsFixed(2)} $symbol';
    } else {
      return '${amount.toStringAsFixed(4)} $symbol';
    }
  }

  String _formatCredits(BigInt credits) {
    // Credits are stored in winc (winston credits), convert to display
    // 1 Credit = 10^12 winc
    final creditValue = credits.toDouble() / 1e12;
    if (creditValue >= 1) {
      return '${creditValue.toStringAsFixed(2)} Credits';
    } else if (creditValue >= 0.01) {
      return '${creditValue.toStringAsFixed(4)} Credits';
    } else {
      // For very small amounts, show more decimal places
      return '${creditValue.toStringAsFixed(6)} Credits';
    }
  }

  String _truncateTxId(String txId) {
    if (txId.length < 20) return txId;
    return '${txId.substring(0, 8)}...${txId.substring(txId.length - 8)}';
  }
}

/// Summary row widget for consistent layout
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final bool isHighlighted;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.subValue,
    this.isHighlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: typography.paragraphNormal(
            color: colors.themeFgMuted,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: typography.paragraphNormal(
                fontWeight:
                    isHighlighted ? ArFontWeight.bold : ArFontWeight.semiBold,
                color: isHighlighted
                    ? colors.themeSuccessDefault
                    : colors.themeFgDefault,
              ),
            ),
            if (subValue != null)
              Text(
                subValue!,
                style: typography.paragraphSmall(
                  color: colors.themeFgMuted,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Error view shown when crypto payment fails.
class CryptoErrorView extends StatelessWidget {
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  const CryptoErrorView({
    super.key,
    this.onRetry,
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
        String errorMessage =
            'An error occurred while processing your payment.';
        String? errorDetails;
        bool canRetry = true;

        if (state is CryptoTopupError) {
          errorMessage = _getErrorMessage(state.errorType);
          errorDetails = state.message;
          canRetry = state.canRetry;
        }

        return Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                Container(
                  color: colors.themeBgCanvas,
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title - left aligned
                      Text(
                        'Payment Failed',
                        style: typography.heading5(
                          fontWeight: ArFontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Icon and message
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ArDriveIcons.triangle(
                            size: 32,
                            color: colors.themeErrorDefault,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  errorMessage,
                                  style: typography.paragraphNormal(
                                    color: colors.themeFgMuted,
                                  ),
                                ),
                                if (errorDetails != null &&
                                    errorDetails.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    errorDetails,
                                    style: typography.paragraphSmall(
                                      color: colors.themeFgMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // No funds charged notice
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: colors.themeBgSubtle,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: colors.themeBorderDefault),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.info_outline,
                              color: colors.themeFgMuted,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Your funds have not been charged.',
                              style: typography.paragraphSmall(
                                color: colors.themeFgDefault,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Action button - right aligned
                      Align(
                        alignment: Alignment.centerRight,
                        child: ArDriveButton(
                          maxHeight: 44,
                          maxWidth: 143,
                          text: canRetry ? 'Try Again' : 'Close',
                          fontStyle: typography.paragraphLarge(
                            fontWeight: ArFontWeight.bold,
                            color: Colors.white,
                          ),
                          onPressed: canRetry ? onRetry : onClose,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // Close button in top right
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

  String _getErrorMessage(CryptoTopupErrorType errorType) {
    switch (errorType) {
      case CryptoTopupErrorType.network:
        return 'Network error occurred. Please check your connection.';
      case CryptoTopupErrorType.transactionRejected:
        return 'You rejected the transaction in your wallet.';
      case CryptoTopupErrorType.insufficientFunds:
        return 'Insufficient funds in your wallet.';
      case CryptoTopupErrorType.insufficientGas:
        return 'Insufficient gas for the transaction.';
      case CryptoTopupErrorType.transactionFailed:
        return 'The transaction failed on the network.';
      case CryptoTopupErrorType.quoteExpired:
        return 'The price quote expired. Please try again.';
      case CryptoTopupErrorType.promoCodeInvalid:
        return 'The promo code is invalid.';
      case CryptoTopupErrorType.sessionExpired:
        return 'Your session expired. Please try again.';
      case CryptoTopupErrorType.unknown:
        return 'An unexpected error occurred.';
    }
  }
}
