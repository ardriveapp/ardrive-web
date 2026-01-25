import 'dart:async';

import 'package:ardrive/turbo/topup/models/crypto_quote.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Displays cryptocurrency quote information with expiration countdown.
class QuoteDisplay extends StatelessWidget {
  final CryptoQuote quote;
  final DateTime? expiresAt;
  final bool showExpiration;
  final VoidCallback? onRefresh;

  const QuoteDisplay({
    super.key,
    required this.quote,
    this.expiresAt,
    this.showExpiration = true,
    this.onRefresh,
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
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with refresh button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Quote Details',
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colorTokens.textHigh,
                ),
              ),
              if (onRefresh != null)
                GestureDetector(
                  onTap: onRefresh,
                  child: Icon(
                    Icons.refresh,
                    size: 18,
                    color: colorTokens.textMid,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // You pay
          _QuoteRow(
            label: 'You pay',
            value: quote.formattedTokenAmount,
            subValue: '\$${quote.usdValue.toStringAsFixed(2)}',
          ),
          const SizedBox(height: 8),

          // You receive (with discount info if applicable)
          _QuoteRowWithDiscount(
            label: 'You receive',
            value: quote.formattedCredits,
            originalValue: quote.hasDiscount &&
                    quote.originalCreditsDisplay != null
                ? '${quote.originalCreditsDisplay!.toStringAsFixed(3)} Credits'
                : null,
            discountPercentage:
                quote.hasDiscount ? quote.discountPercentage : null,
          ),
          const SizedBox(height: 8),

          // Exchange rate
          _QuoteRow(
            label: 'Rate',
            value: '1 ${quote.token.symbol} = ${_calculateRate(quote)}',
          ),

          // Network fee estimate (if applicable)
          if (quote.networkFeeUsd != null && quote.networkFeeUsd! > 0) ...[
            const SizedBox(height: 8),
            _QuoteRow(
              label: 'Est. network fee',
              value: quote.formattedNetworkFee,
            ),
          ],

          // Expiration countdown
          if (showExpiration && expiresAt != null) ...[
            const SizedBox(height: 12),
            _QuoteExpirationTimer(
              expiresAt: expiresAt!,
              onExpired: onRefresh,
            ),
          ],
        ],
      ),
    );
  }

  String _calculateRate(CryptoQuote quote) {
    if (quote.tokenAmount == BigInt.zero || quote.creditsDisplay == 0) {
      return 'N/A';
    }
    // Calculate credits per token
    final creditsPerToken = quote.creditsDisplay / quote.tokenAmountDisplay;
    return '${creditsPerToken.toStringAsFixed(2)} Credits';
  }
}

/// A single row in the quote display
class _QuoteRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;

  const _QuoteRow({
    required this.label,
    required this.value,
    this.subValue,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: typography.paragraphSmall(
            color: colorTokens.textMid,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
            ),
            if (subValue != null)
              Text(
                subValue!,
                style: typography.paragraphSmall(
                  color: colorTokens.textMid,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Quote row with discount display (original price strikethrough + discount badge)
class _QuoteRowWithDiscount extends StatelessWidget {
  final String label;
  final String value;
  final String? originalValue;
  final double? discountPercentage;

  const _QuoteRowWithDiscount({
    required this.label,
    required this.value,
    this.originalValue,
    this.discountPercentage,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final themeColors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    final hasDiscount = originalValue != null &&
        discountPercentage != null &&
        discountPercentage! > 0;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: typography.paragraphSmall(
                color: colorTokens.textMid,
              ),
            ),
            // Discount badge
            if (hasDiscount) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: themeColors.themeSuccessSubtle,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${discountPercentage!.toStringAsFixed(0)}% off',
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: themeColors.themeSuccessDefault,
                  ),
                ),
              ),
            ],
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Original value with strikethrough
            if (hasDiscount)
              Text(
                originalValue!,
                style: typography
                    .paragraphSmall(
                      color: colorTokens.textLow,
                    )
                    .copyWith(
                      decoration: TextDecoration.lineThrough,
                    ),
              ),
            // Current (discounted) value
            Text(
              value,
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.semiBold,
                color: colorTokens.textHigh,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Countdown timer for quote expiration
class _QuoteExpirationTimer extends StatefulWidget {
  final DateTime expiresAt;
  final VoidCallback? onExpired;

  const _QuoteExpirationTimer({
    required this.expiresAt,
    this.onExpired,
  });

  @override
  State<_QuoteExpirationTimer> createState() => _QuoteExpirationTimerState();
}

class _QuoteExpirationTimerState extends State<_QuoteExpirationTimer> {
  late Timer _timer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining();
    });
  }

  @override
  void didUpdateWidget(_QuoteExpirationTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAt != widget.expiresAt) {
      _updateRemaining();
    }
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final remaining = widget.expiresAt.difference(now);

    if (remaining.isNegative) {
      if (_remaining.inSeconds > 0) {
        widget.onExpired?.call();
      }
      setState(() {
        _remaining = Duration.zero;
      });
    } else {
      setState(() {
        _remaining = remaining;
      });
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeColors = ArDriveTheme.of(context).themeData.colors;
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final secondsLeft = _remaining.inSeconds;
    final isExpired = secondsLeft <= 0;
    final isCritical = secondsLeft < 30;
    final isWarning = secondsLeft >= 30 && secondsLeft < 60;

    // Color scheme matching credit card flow:
    // - Red: < 30 seconds (critical)
    // - Yellow/Orange: 30-60 seconds (warning)
    // - Default: > 60 seconds
    Color timerColor;
    if (isExpired || isCritical) {
      timerColor = themeColors.themeErrorDefault;
    } else if (isWarning) {
      timerColor = themeColors.themeWarningMuted;
    } else {
      timerColor = colorTokens.textMid;
    }

    final minutes = _remaining.inMinutes;
    final seconds = _remaining.inSeconds % 60;
    final timeString =
        '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Icon(
          isExpired ? Icons.timer_off : Icons.timer,
          size: 14,
          color: timerColor,
        ),
        const SizedBox(width: 4),
        Text(
          isExpired ? 'Quote expired' : 'Quote expires in $timeString',
          style: typography.paragraphSmall(
            fontWeight: isCritical || isWarning
                ? ArFontWeight.semiBold
                : ArFontWeight.book,
            color: timerColor,
          ),
        ),
      ],
    );
  }
}

/// Compact inline quote summary
class QuoteSummary extends StatelessWidget {
  final CryptoQuote quote;
  final bool showCredits;

  const QuoteSummary({
    super.key,
    required this.quote,
    this.showCredits = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          quote.formattedTokenAmount,
          style: typography.heading5(
            fontWeight: ArFontWeight.bold,
            color: colorTokens.textHigh,
          ),
        ),
        if (showCredits) ...[
          const SizedBox(width: 8),
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: colorTokens.textMid,
          ),
          const SizedBox(width: 8),
          Text(
            quote.formattedCredits,
            style: typography.heading5(
              fontWeight: ArFontWeight.bold,
              color: colorTokens.textHigh,
            ),
          ),
        ],
      ],
    );
  }
}

/// Loading placeholder for quote
class QuoteLoadingPlaceholder extends StatelessWidget {
  const QuoteLoadingPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colorTokens.textMid,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Fetching quote...',
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
        ],
      ),
    );
  }
}
