import 'dart:math';

import 'package:ardrive/turbo/topup/blocs/crypto_topup/crypto_topup_bloc.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
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
  late final ConfettiController _confettiController1;
  late final ConfettiController _confettiController2;

  @override
  void initState() {
    super.initState();
    _confettiController1 = ConfettiController(
      duration: const Duration(seconds: 5),
    );
    _confettiController2 = ConfettiController(
      duration: const Duration(seconds: 5),
    );
    // Start confetti on init
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
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return BlocBuilder<CryptoTopupBloc, CryptoTopupState>(
      builder: (context, state) {
        String creditsAdded = '';
        String? txId;
        CryptoToken? token;

        if (state is CryptoTopupSuccess) {
          // Format BigInt credits as readable string
          creditsAdded = _formatCredits(state.creditsAdded);
          txId = state.txId;
          token = state.token;
        }

        return Stack(
          children: [
            Column(
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
                    child: Stack(
                      children: [
                        // Confetti widgets
                        Align(
                          alignment: Alignment.topLeft,
                          child: ConfettiWidget(
                            numberOfParticles: 15,
                            blastDirection: -pi / 4, // Diagonal right
                            blastDirectionality: BlastDirectionality.explosive,
                            confettiController: _confettiController1,
                            maxBlastForce: 50,
                            minBlastForce: 20,
                            emissionFrequency: 0.05,
                            gravity: 0.2,
                            colors: [
                              colors.themeSuccessDefault,
                              colors.themeAccentDefault,
                              colors.themeFgDefault.withOpacity(0.5),
                            ],
                          ),
                        ),
                        Align(
                          alignment: Alignment.topRight,
                          child: ConfettiWidget(
                            numberOfParticles: 15,
                            blastDirection: -3 * pi / 4, // Diagonal left
                            blastDirectionality: BlastDirectionality.explosive,
                            confettiController: _confettiController2,
                            maxBlastForce: 50,
                            minBlastForce: 20,
                            emissionFrequency: 0.05,
                            gravity: 0.2,
                            colors: [
                              colors.themeSuccessDefault,
                              colors.themeAccentDefault,
                              colors.themeFgDefault.withOpacity(0.5),
                            ],
                          ),
                        ),

                        // Main content
                        Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Success icon
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: colors.themeBgSubtle,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colors.themeBorderDefault,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        Icons.check,
                        size: 48,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Success message
                    Text(
                      'Payment Successful!',
                      style: typography.heading4(
                        fontWeight: ArFontWeight.bold,
                        color: colors.themeFgDefault,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Credits added
                    Text(
                      '$creditsAdded added to your account',
                      style: typography.paragraphLarge(
                        color: colors.themeFgMuted,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    // Transaction ID with explorer link
                    if (txId != null && txId.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.themeBgSubtle,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Transaction ID',
                              style: typography.paragraphSmall(
                                color: colors.themeFgMuted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            SelectableText(
                              _truncateTxId(txId),
                              style: typography.paragraphSmall(
                                fontWeight: ArFontWeight.semiBold,
                                color: colors.themeFgDefault,
                              ),
                            ),
                            if (token != null) ...[
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: () async {
                                  final url = Uri.parse(token!.getExplorerUrl(txId!));
                                  if (await canLaunchUrl(url)) {
                                    await launchUrl(url, mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    ArDriveIcons.newWindow(
                                      size: 14,
                                      color: colors.themeAccentDefault,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'View on ${token.explorerName}',
                                      style: typography.paragraphSmall(
                                        fontWeight: ArFontWeight.semiBold,
                                        color: colors.themeAccentDefault,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 48),

                    // Done button
                    SizedBox(
                      width: 200,
                      height: 48,
                      child: ArDriveButton(
                        text: 'Done',
                        onPressed: widget.onDone,
                      ),
                    ),
                  ],
                ),
              ),
            ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Close button in top right
            Positioned(
              right: 27,
              top: 27,
              child: ArDriveClickArea(
                child: GestureDetector(
                  onTap: widget.onDone,
                  child: ArDriveIcons.x(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatCredits(BigInt credits) {
    // Credits are stored in winston (smallest unit), convert to AR
    // 1 AR = 10^12 winston
    final ar = credits ~/ BigInt.from(1000000000000);
    if (ar >= BigInt.one) {
      return '${ar.toString()} AR';
    }
    // Show in smaller units if less than 1 AR
    final mAR = credits ~/ BigInt.from(1000000000);
    return '${mAR.toString()} mAR';
  }

  String _truncateTxId(String txId) {
    if (txId.length < 20) return txId;
    return '${txId.substring(0, 10)}...${txId.substring(txId.length - 10)}';
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
        String errorMessage = 'An error occurred while processing your payment.';
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
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Error icon
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                color: colors.themeErrorSubtle,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                size: 48,
                                color: colors.themeErrorDefault,
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Error message
                            Text(
                              'Payment Failed',
                              style: typography.heading4(
                                fontWeight: ArFontWeight.bold,
                                color: colors.themeFgDefault,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Error details
                            Text(
                              errorMessage,
                              style: typography.paragraphNormal(
                                color: colors.themeFgMuted,
                              ),
                              textAlign: TextAlign.center,
                            ),

                            if (errorDetails != null && errorDetails.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: colors.themeBgSubtle,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  errorDetails,
                                  style: typography.paragraphSmall(
                                    color: colors.themeFgMuted,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],

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

                            const SizedBox(height: 48),

                            // Action buttons
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (canRetry) ...[
                                  SizedBox(
                                    width: 140,
                                    height: 48,
                                    child: ArDriveButton(
                                      text: 'Try Again',
                                      onPressed: onRetry,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                ],
                                SizedBox(
                                  width: 140,
                                  height: 48,
                                  child: ArDriveButton(
                                    style: ArDriveButtonStyle.secondary,
                                    text: 'Close',
                                    onPressed: onClose,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Close button in top right
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
