import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/payment_method.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
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
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          appLocalizationsOf(context).paymentMethod,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colors.textHigh,
          ),
        ),
        const SizedBox(height: 12),
        ArDriveSegmentedControl<PaymentMethod>(
          expand: true,
          selected: selectedMethod,
          // Only Card calls this: Crypto is chosen through its token menu.
          onSelected: onMethodChanged,
          segments: [
            ArDriveSegment(
              value: PaymentMethod.card,
              label: appLocalizationsOf(context).paymentMethodCard,
              icon: Icons.credit_card,
            ),
            ArDriveSegment(
              value: PaymentMethod.crypto,
              label: selectedToken?.displayName ??
                  appLocalizationsOf(context).paymentMethodCrypto,
              icon: Icons.account_balance_wallet,
              trailingIcon: Icons.keyboard_arrow_down,
              wrap: (context, segment) => PopupMenuButton<CryptoToken>(
                initialValue: selectedToken,
                tooltip: appLocalizationsOf(context).paymentMethodCrypto,
                // Choosing a token switches to crypto; closing the menu
                // without one leaves the method as it was.
                onSelected: (token) {
                  if (selectedMethod != PaymentMethod.crypto) {
                    onMethodChanged(PaymentMethod.crypto);
                  }
                  onTokenSelected(token);
                },
                offset: const Offset(0, 40),
                constraints: const BoxConstraints(minWidth: 300),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ArDriveRadius.md),
                ),
                itemBuilder: _buildTokenMenuItems,
                child: segment,
              ),
            ),
          ],
        ),
      ],
    );
  }

  List<PopupMenuItem<CryptoToken>> _buildTokenMenuItems(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    final availableTokens =
        TokenGroup.allGroups.expand((group) => group.tokens).toList();

    return availableTokens.map((token) {
      return PopupMenuItem<CryptoToken>(
        value: token,
        child: Row(
          children: [
            _TokenIcon(token: token),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                token.displayName,
                style: typography.paragraphNormal(
                  fontWeight: ArFontWeight.semiBold,
                  color: colors.textHigh,
                ),
                overflow: TextOverflow.ellipsis,
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

  static const double _size = 32;

  const _TokenIcon({
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final isSvg = token.logoAsset.endsWith('.svg');

    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: colors.containerRaised,
        borderRadius: BorderRadius.circular(_size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_size / 2),
        child: isSvg
            ? _buildSvgWithFallback(context)
            : Image.asset(
                token.logoAsset,
                width: _size,
                height: _size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackIcon(context),
              ),
      ),
    );
  }

  /// Builds an SVG image with proper error handling using FutureBuilder.
  /// placeholderBuilder only fires during loading, not on errors, so we use
  /// FutureBuilder to handle asset loading failures gracefully.
  Widget _buildSvgWithFallback(BuildContext context) {
    return FutureBuilder<String>(
      future: DefaultAssetBundle.of(context).loadString(token.logoAsset),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData) {
          return _buildFallbackIcon(context);
        }
        return SvgPicture.string(
          snapshot.data!,
          width: _size,
          height: _size,
          fit: BoxFit.cover,
        );
      },
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    return Center(
      child: Text(
        token.symbol
            .substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
        style: const TextStyle(
          fontSize: _size * 0.35,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }
}
