import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A card displaying the purchase summary for top-up transactions.
///
/// Shows credits to receive, price, current balance, and new balance.
class PurchaseSummary extends StatelessWidget {
  /// Credits the user will receive (in winc)
  final BigInt creditsToReceive;

  /// Storage unit (e.g., "GB", "MB")
  final String storageUnit;

  /// Price amount (fiat or token)
  final double priceAmount;

  /// Price currency/token symbol (e.g., "$", "ETH", "ARIO")
  final String priceSymbol;

  /// Whether the price is in token (true) or fiat (false)
  final bool isPriceInToken;

  /// USD equivalent for token prices (optional)
  final double? usdEquivalent;

  /// Current user balance (in winc)
  final BigInt currentBalance;

  /// Current balance estimated storage with unit (e.g., "5.5 GB")
  final String currentBalanceStorage;

  /// New balance estimated storage with unit (e.g., "6.2 GB")
  final String newBalanceStorage;

  /// Whether a promo code discount is applied
  final bool hasPromoDiscount;

  /// Discount percentage (e.g., 10 for 10%)
  final int? discountPercent;

  const PurchaseSummary({
    super.key,
    required this.creditsToReceive,
    required this.storageUnit,
    required this.priceAmount,
    required this.priceSymbol,
    this.isPriceInToken = false,
    this.usdEquivalent,
    required this.currentBalance,
    required this.currentBalanceStorage,
    required this.newBalanceStorage,
    this.hasPromoDiscount = false,
    this.discountPercent,
  });

  BigInt get newBalance => currentBalance + creditsToReceive;

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
          // Credits row (no storage shown here)
          _SummaryRow(
            label: appLocalizationsOf(context).credits,
            value: convertWinstonToLiteralString(creditsToReceive),
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
          const Divider(height: 24),
          // Current balance row with storage
          _SummaryRow(
            label: 'Current Balance',
            value: '${convertWinstonToLiteralString(currentBalance)} ${appLocalizationsOf(context).credits}',
            subValue: '~$currentBalanceStorage',
          ),
          const SizedBox(height: 12),
          // New balance row with storage (highlighted)
          _NewBalanceRow(
            newBalance: newBalance,
            newBalanceStorage: newBalanceStorage,
          ),
        ],
      ),
    );
  }

  String _formatPrice() {
    if (isPriceInToken) {
      // Token amount - show appropriate decimals
      final formatted = priceAmount == priceAmount.roundToDouble()
          ? priceAmount.toInt().toString()
          : priceAmount.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
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

class _NewBalanceRow extends StatelessWidget {
  final BigInt newBalance;
  final String newBalanceStorage;

  const _NewBalanceRow({
    required this.newBalance,
    required this.newBalanceStorage,
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
          'New Balance',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgDefault,
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${convertWinstonToLiteralString(newBalance)} ${appLocalizationsOf(context).credits}',
              style: typography.paragraphNormal(
                fontWeight: ArFontWeight.bold,
                color: colors.themeFgDefault,
              ),
            ),
            Text(
              '~$newBalanceStorage',
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
