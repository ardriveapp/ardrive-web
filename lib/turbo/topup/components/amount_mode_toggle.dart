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
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select by',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgDefault,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: colors.themeBgSubtle,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ToggleButton(
                icon: Icons.cloud_outlined,
                label: 'Storage',
                isSelected: selectedMode == AmountMode.storage,
                onTap: () => onModeChanged(AmountMode.storage),
              ),
              const SizedBox(width: 4),
              _ToggleButton(
                icon: Icons.attach_money,
                label: currencyLabel,
                isSelected: selectedMode == AmountMode.currency,
                onTap: () => onModeChanged(AmountMode.currency),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Material(
      color: isSelected ? colors.themeFgMuted : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? colors.themeBgSurface : colors.themeFgMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color:
                      isSelected ? colors.themeBgSurface : colors.themeFgMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
