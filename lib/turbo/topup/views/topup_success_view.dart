import 'dart:math';

import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/turbo/topup/components/turbo_topup_scaffold.dart';
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

  /// New balance after purchase (formatted credits, e.g., "0.75 Credits")
  final String? newBalanceCredits;

  /// New balance after purchase (formatted storage, e.g., "7.5 GB")
  final String? newBalanceStorage;

  const TurboSuccessView({
    super.key,
    this.amountPaid,
    this.creditsReceived,
    this.storageEstimate,
    this.newBalanceCredits,
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
      // The glossary's lowercase "credits" after an amount.
      newBalanceCredits: newBalanceCredits?.replaceAll(' Credits', ' credits'),
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

  /// New balance after purchase (formatted credits, e.g., "0.75 Credits")
  final String? newBalanceCredits;

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
    this.newBalanceCredits,
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

  /// Formats storage value for display, adding ~ prefix only if not already present
  String _formatStorageSubvalue(String storage) {
    if (storage.startsWith('~')) {
      return storage;
    }
    return '~$storage';
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    ArDriveColorTokens colors, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            color: colors.textMid,
          ),
        ),
        Text(
          value,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            fontWeight: isBold ? ArFontWeight.bold : ArFontWeight.semiBold,
            color: colors.textHigh,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRowWithSubvalue(
    BuildContext context,
    String label,
    String value,
    String? subvalue,
    ArDriveColorTokens colors, {
    bool isHighlighted = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: ArDriveTypographyNew.of(context).paragraphSmall(
            color: colors.textMid,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: ArDriveTypographyNew.of(context).paragraphSmall(
                fontWeight: ArFontWeight.semiBold,
                color: isHighlighted ? colors.statusSuccessFg : colors.textHigh,
              ),
            ),
            if (subvalue != null)
              Text(
                subvalue,
                style: ArDriveTypographyNew.of(context).paragraphSmall(
                  color: colors.textMid,
                ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);
    final creditsReceived = widget.creditsReceived;

    return Stack(
      children: [
        TurboTopupScaffold(
          title: widget.successMessage,
          actions: [
            ModalAction.dismiss(
              title: widget.closeButtonLabel,
              action: () => Navigator.pop(context),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ArDriveNotice(
                type: ArDriveNoticeType.success,
                message: widget.detailMessage,
              ),
              // The credits added are the screen's figure.
              if (creditsReceived != null && creditsReceived.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: creditsReceived,
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
                if (widget.storageEstimate != null)
                  Text(
                    _formatStorageSubvalue(widget.storageEstimate!),
                    style: typography.paragraphNormal(color: colors.textMid),
                  ),
              ],
              if (widget.amountPaid != null ||
                  widget.newBalanceCredits != null ||
                  widget.newBalanceStorage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.containerRaised,
                    borderRadius: BorderRadius.circular(ArDriveRadius.md),
                  ),
                  child: Column(
                    children: [
                      if (widget.amountPaid != null)
                        _buildDetailRow(
                          context,
                          appLocalizationsOf(context).paymentSummaryPaid,
                          widget.amountPaid!,
                          colors,
                        ),
                      if (widget.newBalanceCredits != null ||
                          widget.newBalanceStorage != null) ...[
                        if (widget.amountPaid != null) ...[
                          const SizedBox(height: 12),
                          Divider(color: colors.strokeMid, height: 1),
                          const SizedBox(height: 12),
                        ],
                        _buildDetailRowWithSubvalue(
                          context,
                          appLocalizationsOf(context).paymentSummaryNewBalance,
                          widget.newBalanceCredits ?? widget.newBalanceStorage!,
                          widget.newBalanceCredits != null &&
                                  widget.newBalanceStorage != null
                              ? _formatStorageSubvalue(
                                  widget.newBalanceStorage!)
                              : null,
                          colors,
                          isHighlighted: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        // Confetti, from the top corners.
        if (widget.showConfetti)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ConfettiWidget(
                  numberOfParticles: 10,
                  blastDirection: -pi / 2,
                  blastDirectionality: BlastDirectionality.explosive,
                  confettiController: confettiController1!,
                  maxBlastForce: 40,
                  child: const SizedBox(height: 0, width: 0),
                ),
                ConfettiWidget(
                  numberOfParticles: 10,
                  blastDirection: pi / 2,
                  blastDirectionality: BlastDirectionality.explosive,
                  confettiController: confettiController2!,
                  maxBlastForce: 40,
                  child: const SizedBox(height: 0, width: 0),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
