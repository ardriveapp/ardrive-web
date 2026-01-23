import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// Enum for available top-level payment methods (card vs crypto)
enum TopupPaymentMethod {
  card,
  crypto,
}

/// Payment method selector widget for the Turbo topup flow.
///
/// Displays tabs for selecting between card and crypto payment methods.
class PaymentMethodSelector extends StatelessWidget {
  final TopupPaymentMethod selected;
  final ValueChanged<TopupPaymentMethod> onMethodChanged;

  const PaymentMethodSelector({
    super.key,
    required this.selected,
    required this.onMethodChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _PaymentMethodTab(
              label: 'Card',
              icon: Icons.credit_card,
              isSelected: selected == TopupPaymentMethod.card,
              onTap: () => onMethodChanged(TopupPaymentMethod.card),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _PaymentMethodTab(
              label: 'Crypto',
              icon: Icons.account_balance_wallet,
              isSelected: selected == TopupPaymentMethod.crypto,
              onTap: () => onMethodChanged(TopupPaymentMethod.crypto),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentMethodTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? colorTokens.containerL3 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? colorTokens.textHigh : colorTokens.textMid,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: typography.paragraphNormal(
                fontWeight:
                    isSelected ? ArFontWeight.semiBold : ArFontWeight.book,
                color: isSelected ? colorTokens.textHigh : colorTokens.textMid,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
