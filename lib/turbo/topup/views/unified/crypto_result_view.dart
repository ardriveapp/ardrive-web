import 'dart:math';

import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Success view shown after successful crypto payment.
class CryptoSuccessView extends StatefulWidget {
  final VoidCallback? onDone;

  const CryptoSuccessView({
    super.key,
    this.onDone,
  });

  @override
  State<CryptoSuccessView> createState() => _CryptoSuccessViewState();
}

class _CryptoSuccessViewState extends State<CryptoSuccessView> {
  final ConfettiController _confettiController1 = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  final ConfettiController _confettiController2 = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    _confettiController1.play();
    _confettiController2.play();
  }

  @override
  void dispose() {
    _confettiController1.dispose();
    _confettiController2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final onDone = widget.onDone;

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        if (state is! CryptoTopupSuccess) {
          return const SizedBox.shrink();
        }

        final token = state.token;
        final txId = state.txId;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            // The same layout as the card payment's success screen.
            TurboTopupScaffold(
              title: appLocalizationsOf(context).paymentSuccessful,
              canClose: onDone != null,
              onClose: onDone,
              actions: [
                if (onDone != null)
                  ModalAction.dismiss(
                    title: appLocalizationsOf(context).close,
                    action: onDone,
                  ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ArDriveNotice(
                    type: ArDriveNoticeType.success,
                    message: appLocalizationsOf(context)
                        .yourCreditsWillBeAddedToYourAccount,
                  ),
                  // One card for the result: the credits added as its
                  // figure, then what was paid and the new balance.
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colors.containerRaised,
                      borderRadius: BorderRadius.circular(ArDriveRadius.md),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: _formatCredits(state.creditsAdded),
                                style: typography.heading2(
                                  color: colors.textHigh,
                                  fontWeight: ArFontWeight.light,
                                ),
                              ),
                              TextSpan(
                                text: ' credits added',
                                style: typography.paragraphLarge(
                                  color: colors.textMid,
                                  fontWeight: ArFontWeight.semiBold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (state.storageEstimate != null)
                          Text(
                            _approximately(state.storageEstimate!),
                            style: typography.paragraphNormal(
                                color: colors.textMid),
                          ),
                        const SizedBox(height: 12),
                        Divider(color: colors.strokeMid, height: 1),
                        const SizedBox(height: 12),
                        _SummaryRow(
                          label: 'Paid',
                          value: _formatTokenAmount(
                              state.tokenAmountSpent, token.symbol),
                          subValue: state.usdValue != null
                              ? '\$${state.usdValue!.toStringAsFixed(2)}'
                              : null,
                        ),
                        if (state.newBalance != null) ...[
                          const SizedBox(height: 12),
                          Divider(color: colors.strokeMid, height: 1),
                          const SizedBox(height: 12),
                          _SummaryRow(
                            label: 'New balance',
                            value:
                                '${_formatCredits(state.newBalance!)} credits',
                            subValue: state.newBalanceStorage != null
                                ? _approximately(state.newBalanceStorage!)
                                : null,
                            isHighlighted: true,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Transaction ID as a link to the explorer, in monospace
                  if (txId.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text(
                          'Transaction: ',
                          style: typography.paragraphSmall(
                            color: colors.textMid,
                          ),
                        ),
                        Flexible(
                          child: ArDriveLink(
                            text: _truncateTxId(txId),
                            style: typography.code(fontSize: 12),
                            external: true,
                            onTap: () async {
                              final url = Uri.parse(token.getExplorerUrl(txId));
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url,
                                    mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            // Confetti (at the top, blasting downward into the content)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ConfettiWidget(
                    numberOfParticles: 15,
                    blastDirection: pi / 4, // Down and to the right
                    blastDirectionality: BlastDirectionality.explosive,
                    confettiController: _confettiController1,
                    maxBlastForce: 30,
                    minBlastForce: 10,
                    gravity: 0.2,
                    emissionFrequency: 0.05,
                    child: const SizedBox(height: 0, width: 0),
                  ),
                  ConfettiWidget(
                    numberOfParticles: 15,
                    blastDirection: 3 * pi / 4, // Down and to the left
                    blastDirectionality: BlastDirectionality.explosive,
                    confettiController: _confettiController2,
                    maxBlastForce: 30,
                    minBlastForce: 10,
                    gravity: 0.2,
                    emissionFrequency: 0.05,
                    child: const SizedBox(height: 0, width: 0),
                  ),
                ],
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
      return creditValue.toStringAsFixed(2);
    } else if (creditValue >= 0.01) {
      return creditValue.toStringAsFixed(4);
    } else {
      // For very small amounts, show more decimal places
      return creditValue.toStringAsFixed(6);
    }
  }

  /// A storage estimate, marked as approximate once.
  String _approximately(String storage) =>
      storage.startsWith('~') ? storage : '~$storage';

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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: typography.paragraphNormal(
            color: colors.textMid,
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
                color: isHighlighted ? colors.statusSuccessFg : colors.textHigh,
              ),
            ),
            if (subValue != null)
              Text(
                subValue!,
                style: typography.paragraphSmall(
                  color: colors.textMid,
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
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

        final action = canRetry ? onRetry : onClose;

        return TurboTopupScaffold(
          title: 'Payment failed',
          canClose: onClose != null,
          onClose: onClose,
          actions: [
            ModalAction(
              title: canRetry ? 'Try again' : 'Close',
              isEnable: action != null,
              action: action ?? () {},
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArDriveNotice(
                type: ArDriveNoticeType.error,
                message: errorMessage,
              ),
              if (errorDetails != null && errorDetails.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  errorDetails,
                  style: typography.paragraphSmall(
                    color: colors.textMid,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // No funds charged notice
              const ArDriveNotice(
                type: ArDriveNoticeType.info,
                message: 'Your funds have not been charged.',
              ),
            ],
          ),
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
