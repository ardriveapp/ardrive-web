import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A simplified purchase summary for the payment method selection page.
///
/// Shows only: credits to receive, storage estimate, price, and discount (if applicable).
/// Balance information is shown on the final checkout page instead.
class PurchaseSummary extends StatelessWidget {
  /// Credits the user will receive (in winc)
  final BigInt creditsToReceive;

  /// Estimated storage amount (e.g., "5.00")
  final String? storageEstimate;

  /// Storage unit (e.g., "GB", "TB")
  final String? storageUnit;

  /// Price amount (fiat or token)
  final double priceAmount;

  /// Price currency/token symbol (e.g., "$", "ETH", "ARIO")
  final String priceSymbol;

  /// Whether the price is in token (true) or fiat (false)
  final bool isPriceInToken;

  /// USD equivalent for token prices (optional)
  final double? usdEquivalent;

  /// Whether a promo code discount is applied
  final bool hasPromoDiscount;

  /// Discount percentage (e.g., 10 for 10%)
  final int? discountPercent;

  const PurchaseSummary({
    super.key,
    required this.creditsToReceive,
    this.storageEstimate,
    this.storageUnit,
    required this.priceAmount,
    required this.priceSymbol,
    this.isPriceInToken = false,
    this.usdEquivalent,
    this.hasPromoDiscount = false,
    this.discountPercent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    // Don't show if no amount selected
    if (priceAmount <= 0) {
      return const SizedBox.shrink();
    }

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
          Text(
            'Purchase Summary',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.bold,
              color: colors.themeFgDefault,
            ),
          ),
          const SizedBox(height: 16),
          // Credits row with storage
          _SummaryRow(
            label: appLocalizationsOf(context).credits,
            value: convertWinstonToLiteralString(creditsToReceive),
            // Note: storageEstimate may already include the unit from formatStorageWithDynamicUnit
            // If storageUnit is null, assume storageEstimate is complete (e.g., "5.0 GB")
            // If storageUnit is provided, append it (for backwards compatibility)
            subValue: storageEstimate != null
                ? storageUnit != null
                    ? '~$storageEstimate $storageUnit'
                    : '~$storageEstimate'
                : null,
          ),
          const SizedBox(height: 12),
          // Price row
          _SummaryRow(
            label: 'Price',
            value: _formatPrice(),
            subValue: isPriceInToken && usdEquivalent != null
                ? '~\$${NumberFormat('#,##0.00').format(usdEquivalent)}'
                : null,
          ),
          // Discount row (if applicable)
          if (hasPromoDiscount && discountPercent != null) ...[
            const SizedBox(height: 12),
            _SummaryRow(
              label: 'Discount',
              value: '$discountPercent% off',
              valueColor: colors.themeSuccessDefault,
            ),
          ],
        ],
      ),
    );
  }

  String _formatPrice() {
    if (isPriceInToken) {
      // Token amount - show appropriate decimals
      final formatted = priceAmount == priceAmount.roundToDouble()
          ? priceAmount.toInt().toString()
          : priceAmount
              .toStringAsFixed(4)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');
      return '$formatted $priceSymbol';
    } else {
      // Fiat amount
      return '$priceSymbol${NumberFormat('#,##0.00').format(priceAmount)}';
    }
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.subValue,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
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
                fontWeight: ArFontWeight.semiBold,
                color: valueColor ?? colors.themeFgDefault,
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

/// A loading placeholder for purchase summary
class PurchaseSummaryLoading extends StatelessWidget {
  const PurchaseSummaryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      ),
    );
  }
}

/// A comprehensive checkout summary for final checkout pages.
///
/// Shows complete purchase details including:
/// - Credits to receive with storage estimate
/// - Price breakdown (subtotal, discount, total)
/// - Current Turbo balance with storage
/// - New Turbo balance with storage
/// - For crypto: token balance before/after
class CheckoutSummary extends StatelessWidget {
  /// Credits the user will receive (in winc)
  final BigInt creditsToReceive;

  /// Storage estimate for credits to receive
  final String storageEstimate;

  /// Price amount (fiat or token)
  final double priceAmount;

  /// Price currency/token symbol (e.g., "$", "ETH", "ARIO")
  final String priceSymbol;

  /// Whether the price is in token (true) or fiat (false)
  final bool isPriceInToken;

  /// Subtotal before discount (optional, for card payments with promo)
  final double? subtotal;

  /// Discount percentage (e.g., 10 for 10%)
  final int? discountPercent;

  /// Current Turbo balance (in winc)
  final BigInt currentBalance;

  /// Storage estimate for current balance
  final String currentBalanceStorage;

  /// New Turbo balance (in winc) - calculated if not provided
  final BigInt? newBalance;

  /// Storage estimate for new balance
  final String newBalanceStorage;

  /// Token symbol for crypto payments (e.g., "ARIO", "ETH")
  final String? tokenSymbol;

  /// Current token balance in wallet (for crypto payments)
  final double? tokenBalance;

  /// Token balance after payment (for crypto payments)
  final double? tokenBalanceAfter;

  /// Network fee estimate (for EVM tokens)
  final String? networkFeeEstimate;

  /// Applied promo code (optional)
  final String? promoCode;

  /// USD equivalent for token prices (optional)
  final double? usdEquivalent;

  const CheckoutSummary({
    super.key,
    required this.creditsToReceive,
    required this.storageEstimate,
    required this.priceAmount,
    required this.priceSymbol,
    this.isPriceInToken = false,
    this.subtotal,
    this.discountPercent,
    required this.currentBalance,
    required this.currentBalanceStorage,
    this.newBalance,
    required this.newBalanceStorage,
    this.tokenSymbol,
    this.tokenBalance,
    this.tokenBalanceAfter,
    this.networkFeeEstimate,
    this.promoCode,
    this.usdEquivalent,
  });

  BigInt get _newBalance => newBalance ?? (currentBalance + creditsToReceive);

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
          // Section 1: What you're buying
          _CompactRow(
            label: "You're buying",
            value: '${convertWinstonToLiteralString(creditsToReceive)} credits',
            subValue: '~$storageEstimate',
            typography: typography,
            colors: colors,
          ),
          const SizedBox(height: 12),
          Divider(color: colors.themeBorderDefault, height: 1),
          const SizedBox(height: 12),

          // Section 2: Payment details
          // Subtotal (if discount applies)
          if (subtotal != null && discountPercent != null) ...[
            _CompactRow(
              label: 'Subtotal',
              value: _formatFiatPrice(subtotal!),
              typography: typography,
              colors: colors,
              isMuted: true,
            ),
            const SizedBox(height: 6),
          ],

          // Promo code (if applied)
          if (promoCode != null && promoCode!.isNotEmpty) ...[
            _CompactRow(
              label: 'Promo code',
              value: promoCode!,
              typography: typography,
              colors: colors,
              valueColor: colors.themeSuccessDefault,
            ),
            const SizedBox(height: 6),
          ],

          // Discount (if applies)
          if (discountPercent != null) ...[
            _CompactRow(
              label: 'Discount',
              value: '-$discountPercent%',
              typography: typography,
              colors: colors,
              valueColor: colors.themeSuccessDefault,
            ),
            const SizedBox(height: 6),
          ],

          // Total/Amount
          _CompactRow(
            label: isPriceInToken ? 'You pay' : 'Total',
            value: _formatPrice(),
            subValue: isPriceInToken && usdEquivalent != null
                ? '~\$${NumberFormat('#,##0.00').format(usdEquivalent)}'
                : null,
            typography: typography,
            colors: colors,
            isBold: true,
          ),

          // Network fee (for EVM tokens)
          if (networkFeeEstimate != null) ...[
            const SizedBox(height: 6),
            _CompactRow(
              label: 'Est. network fee',
              value: networkFeeEstimate!,
              typography: typography,
              colors: colors,
              isMuted: true,
            ),
          ],

          // Token balance (for crypto payments)
          if (isPriceInToken &&
              tokenSymbol != null &&
              tokenBalance != null) ...[
            const SizedBox(height: 12),
            Divider(color: colors.themeBorderDefault, height: 1),
            const SizedBox(height: 12),
            _CompactRow(
              label: '$tokenSymbol balance',
              value: _formatTokenAmount(tokenBalance!),
              typography: typography,
              colors: colors,
            ),
            const SizedBox(height: 6),
            _CompactRow(
              label: 'After purchase',
              value: _formatTokenAmount(
                  tokenBalanceAfter ?? (tokenBalance! - priceAmount)),
              typography: typography,
              colors: colors,
            ),
          ],

          const SizedBox(height: 12),
          Divider(color: colors.themeBorderDefault, height: 1),
          const SizedBox(height: 12),

          // Section 3: Turbo Credits Balance
          _CompactRow(
            label: 'Current balance',
            value: '${convertWinstonToLiteralString(currentBalance)} credits',
            subValue: '~$currentBalanceStorage',
            typography: typography,
            colors: colors,
          ),
          const SizedBox(height: 6),
          _CompactRow(
            label: 'After purchase',
            value: '${convertWinstonToLiteralString(_newBalance)} credits',
            subValue: '~$newBalanceStorage',
            typography: typography,
            colors: colors,
            isBold: true,
            valueColor: colors.themeSuccessDefault,
          ),
        ],
      ),
    );
  }

  String _formatPrice() {
    if (isPriceInToken) {
      final formatted = priceAmount == priceAmount.roundToDouble()
          ? priceAmount.toInt().toString()
          : priceAmount
              .toStringAsFixed(4)
              .replaceAll(RegExp(r'0+$'), '')
              .replaceAll(RegExp(r'\.$'), '');
      return '$formatted $priceSymbol';
    } else {
      return _formatFiatPrice(priceAmount);
    }
  }

  String _formatFiatPrice(double amount) {
    return '\$${NumberFormat('#,##0.00').format(amount)}';
  }

  String _formatTokenAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '${amount.toInt()} $tokenSymbol';
    }
    return '${amount.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')} $tokenSymbol';
  }
}

/// Compact row with consistent font sizes for cleaner summaries
class _CompactRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subValue;
  final ArdriveTypographyNew typography;
  final ArDriveColors colors;
  final bool isBold;
  final bool isMuted;
  final Color? valueColor;

  const _CompactRow({
    required this.label,
    required this.value,
    this.subValue,
    required this.typography,
    required this.colors,
    this.isBold = false,
    this.isMuted = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: typography.paragraphSmall(
            fontWeight: isBold ? ArFontWeight.semiBold : ArFontWeight.book,
            color: isMuted ? colors.themeFgMuted : colors.themeFgDefault,
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: typography.paragraphSmall(
                  fontWeight:
                      isBold ? ArFontWeight.bold : ArFontWeight.semiBold,
                  color: valueColor ??
                      (isMuted ? colors.themeFgMuted : colors.themeFgDefault),
                ),
                textAlign: TextAlign.end,
              ),
              if (subValue != null)
                Text(
                  subValue!,
                  style: typography.paragraphSmall(
                    color: colors.themeFgMuted,
                  ),
                  textAlign: TextAlign.end,
                ),
            ],
          ),
        ),
      ],
    );
  }
}
