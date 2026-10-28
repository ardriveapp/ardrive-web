import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// The mode for selecting the top-up amount
enum AmountMode {
  /// Select amount by storage size (MiB, GiB, TiB)
  storage,

  /// Select amount by currency (USD for card, token amount for crypto)
  currency,
}

/// Toggle between storage-based and currency-based amount selection.
class AmountModeToggle extends StatelessWidget {
  final AmountMode selectedMode;
  final ValueChanged<AmountMode> onModeChanged;

  /// Label for the currency mode (e.g., "USD" for card, "Token" for crypto)
  final String currencyLabel;

  const AmountModeToggle({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.currencyLabel = 'USD',
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select by',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textHigh,
          ),
        ),
        const SizedBox(height: 8),
        ArDriveSegmentedControl<AmountMode>(
          selected: selectedMode,
          onSelected: onModeChanged,
          segments: [
            const ArDriveSegment(
              value: AmountMode.storage,
              label: 'Storage',
              icon: Icons.cloud_outlined,
            ),
            ArDriveSegment(
              value: AmountMode.currency,
              label: currencyLabel,
              // A dollar sign for USD only: SOL or ETH was shown with one.
              icon: currencyLabel == 'USD'
                  ? Icons.attach_money
                  : Icons.toll_outlined,
            ),
          ],
        ),
      ],
    );
  }
}
