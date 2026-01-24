import 'package:ardrive/turbo/topup/models/payment_method.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

extension PaymentMethodExtension on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.card:
        return 'Card';
      case PaymentMethod.crypto:
        return 'Crypto';
    }
  }

  IconData get icon {
    switch (this) {
      case PaymentMethod.card:
        return Icons.credit_card;
      case PaymentMethod.crypto:
        return Icons.account_balance_wallet;
    }
  }
}

/// Tab switcher for payment methods (Card vs Crypto)
class PaymentMethodTabs extends StatelessWidget {
  final PaymentMethod selectedMethod;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final bool isDisabled;

  const PaymentMethodTabs({
    super.key,
    required this.selectedMethod,
    required this.onMethodChanged,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colorTokens.containerL1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorTokens.strokeLow),
      ),
      child: Row(
        children: PaymentMethod.values.map((method) {
          return Expanded(
            child: _PaymentMethodTab(
              method: method,
              isSelected: selectedMethod == method,
              isDisabled: isDisabled,
              onTap: () => onMethodChanged(method),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _PaymentMethodTab extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _PaymentMethodTab({
    required this.method,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorTokens.containerL3
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                method.icon,
                size: 18,
                color: isSelected
                    ? colorTokens.textHigh
                    : colorTokens.textMid,
              ),
              const SizedBox(width: 8),
              Text(
                method.displayName,
                style: typography.paragraphNormal(
                  fontWeight:
                      isSelected ? ArFontWeight.semiBold : ArFontWeight.book,
                  color: isSelected
                      ? colorTokens.textHigh
                      : colorTokens.textMid,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A more compact inline version for smaller spaces
class PaymentMethodPills extends StatelessWidget {
  final PaymentMethod selectedMethod;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final bool isDisabled;

  const PaymentMethodPills({
    super.key,
    required this.selectedMethod,
    required this.onMethodChanged,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: PaymentMethod.values.map((method) {
        final isSelected = selectedMethod == method;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: _PaymentMethodPill(
            method: method,
            isSelected: isSelected,
            isDisabled: isDisabled,
            onTap: () => onMethodChanged(method),
          ),
        );
      }).toList(),
    );
  }
}

class _PaymentMethodPill extends StatelessWidget {
  final PaymentMethod method;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback onTap;

  const _PaymentMethodPill({
    required this.method,
    required this.isSelected,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorTokens.containerL3
              : colorTokens.containerL1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? colorTokens.strokeHigh
                : colorTokens.strokeLow,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Text(
            method.displayName,
            style: typography.paragraphSmall(
              fontWeight:
                  isSelected ? ArFontWeight.semiBold : ArFontWeight.book,
              color: isSelected
                  ? colorTokens.textHigh
                  : colorTokens.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
