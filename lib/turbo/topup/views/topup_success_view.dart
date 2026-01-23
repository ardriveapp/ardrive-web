import 'dart:math';

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

class TurboSuccessView extends StatelessWidget {
  /// Amount paid (formatted, e.g., "$25.00")
  final String? amountPaid;

  /// Credits received (formatted, e.g., "0.25 AR")
  final String? creditsReceived;

  /// Storage estimate for credits received (e.g., "2.5 GB")
  final String? storageEstimate;

  /// New balance after purchase (formatted storage, e.g., "7.5 GB")
  final String? newBalanceStorage;

  const TurboSuccessView({
    super.key,
    this.amountPaid,
    this.creditsReceived,
    this.storageEstimate,
    this.newBalanceStorage,
  });

  @override
  Widget build(BuildContext context) {
    return SuccessView(
      successMessage: appLocalizationsOf(context).paymentSuccessful,
      detailMessage:
          appLocalizationsOf(context).yourCreditsWillBeAddedToYourAccount,
      closeButtonLabel: appLocalizationsOf(context).close,
      showConfetti: true,
      amountPaid: amountPaid,
      creditsReceived: creditsReceived,
      storageEstimate: storageEstimate,
      newBalanceStorage: newBalanceStorage,
    );
  }
}

class SuccessView extends StatefulWidget {
  final String successMessage;
  final String detailMessage;
  final String closeButtonLabel;
  final bool showConfetti;

  /// Amount paid (formatted, e.g., "$25.00")
  final String? amountPaid;

  /// Credits received (formatted, e.g., "0.25 AR")
  final String? creditsReceived;

  /// Storage estimate for credits received (e.g., "2.5 GB")
  final String? storageEstimate;

  /// New balance after purchase (formatted storage, e.g., "7.5 GB")
  final String? newBalanceStorage;

  const SuccessView({
    super.key,
    required this.successMessage,
    required this.detailMessage,
    required this.closeButtonLabel,
    this.showConfetti = false,
    this.amountPaid,
    this.creditsReceived,
    this.storageEstimate,
    this.newBalanceStorage,
  });

  @override
  State<SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<SuccessView> {
  final ConfettiController? confettiController1 = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  final ConfettiController? confettiController2 = ConfettiController(
    duration: const Duration(seconds: 5),
  );

  @override
  void initState() {
    super.initState();
    if (widget.showConfetti) {
      confettiController1!.play();
      confettiController2!.play();
    }
  }

  bool get _hasPaymentDetails =>
      widget.amountPaid != null ||
      widget.storageEstimate != null ||
      widget.newBalanceStorage != null;

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    ArDriveColors colors, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            color: colors.themeFgMuted,
          ),
        ),
        Text(
          value,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            fontWeight: isBold ? ArFontWeight.bold : ArFontWeight.semiBold,
            color: colors.themeFgDefault,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeData = ArDriveTheme.of(context).themeData;
    final colors = themeData.colors;
    final colorTokens = themeData.colorTokens;

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
                child: Column(
                  children: [
                    if (widget.showConfetti)
                      Row(
                        mainAxisSize: MainAxisSize.max,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ConfettiWidget(
                            numberOfParticles: 10,
                            blastDirection: -pi / 2,
                            blastDirectionality: BlastDirectionality.explosive,
                            confettiController: confettiController1!,
                            maxBlastForce: 40,
                            child: const SizedBox(
                              height: 0,
                              width: 0,
                            ),
                          ),
                          ConfettiWidget(
                            numberOfParticles: 10,
                            blastDirection: pi / 2,
                            blastDirectionality: BlastDirectionality.explosive,
                            confettiController: confettiController2!,
                            maxBlastForce: 40,
                            child: const SizedBox(
                              height: 0,
                              width: 0,
                            ),
                          ),
                        ],
                      ),
                    const Spacer(),
                    // Success icon and message
                    Column(
                      children: [
                        ArDriveIcons.checkCirle(
                          size: 40,
                          color: colors.themeSuccessDefault,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.successMessage,
                          style: ArDriveTypographyNew.of(context).heading5(
                            fontWeight: ArFontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.detailMessage,
                          style: ArDriveTypographyNew.of(context).paragraphNormal(
                            color: colors.themeFgMuted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        // Purchase details
                        if (_hasPaymentDetails) ...[
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colors.themeBgSubtle,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              children: [
                                if (widget.amountPaid != null)
                                  _buildDetailRow(
                                    context,
                                    'Amount Paid',
                                    widget.amountPaid!,
                                    colors,
                                  ),
                                if (widget.storageEstimate != null) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow(
                                    context,
                                    'Storage Added',
                                    widget.storageEstimate!,
                                    colors,
                                  ),
                                ],
                                if (widget.newBalanceStorage != null) ...[
                                  const SizedBox(height: 8),
                                  _buildDetailRow(
                                    context,
                                    'New Balance',
                                    widget.newBalanceStorage!,
                                    colors,
                                    isBold: true,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const Spacer(),
                    // Close button
                    Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: ArDriveButton(
                        maxHeight: 44,
                        maxWidth: 143,
                        text: widget.closeButtonLabel,
                        fontStyle: ArDriveTypographyNew.of(context).paragraphLarge(
                          fontWeight: ArFontWeight.bold,
                          color: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                        },
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
              onTap: () => Navigator.pop(context),
              child: ArDriveIcons.x(),
            ),
          ),
        ),
      ],
    );
  }
}
