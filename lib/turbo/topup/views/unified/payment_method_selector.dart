import 'package:ardrive/turbo/topup/models/payment_method.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A selector widget for choosing between Card and Crypto payment methods.
///
/// Displays as a radio button group with expandable sections for each method.
class PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selectedMethod;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final Widget cardContent;
  final Widget cryptoContent;
  final bool isLoading;

  const PaymentMethodSelector({
    super.key,
    required this.selectedMethod,
    required this.onMethodChanged,
    required this.cardContent,
    required this.cryptoContent,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Text(
          'Payment Method',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgMuted,
          ),
        ),
        const SizedBox(height: 16),

        // Card option
        _PaymentMethodOption(
          title: 'Credit or Debit Card',
          subtitle: 'Visa, Mastercard, Amex, Discover',
          icon: Icons.credit_card,
          isSelected: selectedMethod == PaymentMethod.card,
          isExpanded: selectedMethod == PaymentMethod.card,
          onTap: () => onMethodChanged(PaymentMethod.card),
          expandedContent: cardContent,
        ),
        const SizedBox(height: 12),

        // Crypto option
        _PaymentMethodOption(
          title: 'Pay with Crypto',
          subtitle: 'ARIO • ETH • SOL • USDC — No KYC required',
          icon: Icons.account_balance_wallet,
          isSelected: selectedMethod == PaymentMethod.crypto,
          isExpanded: selectedMethod == PaymentMethod.crypto,
          onTap: () => onMethodChanged(PaymentMethod.crypto),
          expandedContent: cryptoContent,
          badge: 'New',
        ),
      ],
    );
  }
}

/// Individual payment method option with radio button and expandable content
class _PaymentMethodOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final bool isExpanded;
  final VoidCallback onTap;
  final Widget expandedContent;
  final String? badge;

  const _PaymentMethodOption({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.isExpanded,
    required this.onTap,
    required this.expandedContent,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: isSelected ? colors.themeBgSubtle : colors.themeBgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? colors.themeFgMuted : colors.themeBorderDefault,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          // Header row (always visible)
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Radio button
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? colors.themeFgDefault
                            : colors.themeBorderDefault,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? Center(
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: colors.themeFgDefault,
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // Icon
                  Icon(
                    icon,
                    size: 24,
                    color: isSelected
                        ? colors.themeFgDefault
                        : colors.themeFgMuted,
                  ),
                  const SizedBox(width: 12),

                  // Text content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              title,
                              style: typography.paragraphNormal(
                                fontWeight: ArFontWeight.semiBold,
                                color: colors.themeFgDefault,
                              ),
                            ),
                            if (badge != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.themeAccentSubtle,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  badge!,
                                  style: typography.caption(
                                    fontWeight: ArFontWeight.bold,
                                    color: colors.themeAccentDefault,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: typography.paragraphSmall(
                            color: colors.themeFgMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expandable content
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16,
              ),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  expandedContent,
                ],
              ),
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}

/// Simple card payment content placeholder that wraps existing Stripe fields
class CardPaymentContent extends StatelessWidget {
  final Widget stripeFields;

  const CardPaymentContent({
    super.key,
    required this.stripeFields,
  });

  @override
  Widget build(BuildContext context) {
    return stripeFields;
  }
}
