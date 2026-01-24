import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/payment_method.dart';
export 'package:ardrive/turbo/topup/models/payment_method.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Selector for choosing between card and crypto payment methods.
///
/// Card is shown as a tab, while crypto shows a dropdown of available tokens.
class PaymentMethodSelector extends StatelessWidget {
  final PaymentMethod selectedMethod;
  final CryptoToken? selectedToken;
  final ValueChanged<PaymentMethod> onMethodChanged;
  final ValueChanged<CryptoToken> onTokenSelected;

  const PaymentMethodSelector({
    super.key,
    required this.selectedMethod,
    this.selectedToken,
    required this.onMethodChanged,
    required this.onTokenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Payment Method',
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.themeFgDefault,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colors.themeBorderDefault),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              // Card payment tab
              Expanded(
                child: _PaymentTab(
                  icon: Icons.credit_card,
                  label: 'Credit/Debit Card',
                  isSelected: selectedMethod == PaymentMethod.card,
                  onTap: () => onMethodChanged(PaymentMethod.card),
                  isFirst: true,
                ),
              ),
              // Crypto payment tab with dropdown
              Expanded(
                child: _CryptoPaymentTab(
                  isSelected: selectedMethod == PaymentMethod.crypto,
                  selectedToken: selectedToken,
                  onTap: () {
                    if (selectedMethod != PaymentMethod.crypto) {
                      onMethodChanged(PaymentMethod.crypto);
                    }
                  },
                  onTokenSelected: (token) {
                    onMethodChanged(PaymentMethod.crypto);
                    onTokenSelected(token);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Individual payment method tab
class _PaymentTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFirst;

  const _PaymentTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.isFirst = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Material(
      color: isSelected ? colors.themeFgMuted : colors.themeBgSurface,
      borderRadius: BorderRadius.only(
        topLeft: isFirst ? const Radius.circular(7) : Radius.zero,
        bottomLeft: isFirst ? const Radius.circular(7) : Radius.zero,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.only(
          topLeft: isFirst ? const Radius.circular(7) : Radius.zero,
          bottomLeft: isFirst ? const Radius.circular(7) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isSelected ? colors.themeBgSurface : colors.themeFgMuted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: isSelected
                        ? colors.themeBgSurface
                        : colors.themeFgMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Crypto payment tab with token dropdown
class _CryptoPaymentTab extends StatelessWidget {
  final bool isSelected;
  final CryptoToken? selectedToken;
  final VoidCallback onTap;
  final ValueChanged<CryptoToken> onTokenSelected;

  const _CryptoPaymentTab({
    required this.isSelected,
    this.selectedToken,
    required this.onTap,
    required this.onTokenSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Material(
      color: isSelected ? colors.themeFgMuted : colors.themeBgSurface,
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(7),
        bottomRight: Radius.circular(7),
      ),
      child: PopupMenuButton<CryptoToken>(
        initialValue: selectedToken,
        onSelected: (token) {
          onTap(); // Also trigger the onTap to select crypto method
          onTokenSelected(token);
        },
        onCanceled: onTap, // Select crypto method even if menu is dismissed
        offset: const Offset(0, 48),
        constraints: const BoxConstraints(minWidth: 300),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        itemBuilder: (context) => _buildTokenMenuItems(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 18,
                color:
                    isSelected ? colors.themeBgSurface : colors.themeFgMuted,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  selectedToken?.displayName ?? 'Crypto',
                  style: typography.paragraphSmall(
                    fontWeight: ArFontWeight.semiBold,
                    color: isSelected
                        ? colors.themeBgSurface
                        : colors.themeFgMuted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color:
                    isSelected ? colors.themeBgSurface : colors.themeFgMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PopupMenuItem<CryptoToken>> _buildTokenMenuItems(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return CryptoToken.values.map((token) {
      // ARIO tokens have no Turbo fee (no 20% upcharge), but may still have gas fees
      final hasNoTurboFee = token == CryptoToken.arioAO ||
          token == CryptoToken.arioAOViaEth ||
          token == CryptoToken.arioBase;

      return PopupMenuItem<CryptoToken>(
        value: token,
        child: Row(
          children: [
            _TokenIcon(token: token),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      token.displayName,
                      style: typography.paragraphNormal(
                        fontWeight: ArFontWeight.semiBold,
                        color: colors.themeFgDefault,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (hasNoTurboFee) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.themeBgSubtle,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.themeBorderDefault),
                      ),
                      child: Text(
                        'No Turbo Fee',
                        style: typography.caption(
                          fontWeight: ArFontWeight.semiBold,
                          color: colors.themeFgMuted,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

/// Token icon widget
class _TokenIcon extends StatelessWidget {
  final CryptoToken token;
  final double size;

  const _TokenIcon({
    required this.token,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final isSvg = token.logoAsset.endsWith('.svg');

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.themeBgSubtle,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: isSvg
            ? SvgPicture.asset(
                token.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                placeholderBuilder: (context) => _buildFallbackIcon(context),
              )
            : Image.asset(
                token.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackIcon(context),
              ),
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    return Center(
      child: Text(
        token.symbol.substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
