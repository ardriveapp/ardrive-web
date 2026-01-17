import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A card widget displaying a cryptocurrency token option for selection.
///
/// Shows the token icon, name, and optional balance information.
class TokenCard extends StatelessWidget {
  final CryptoToken token;
  final TokenBalance? balance;
  final bool isSelected;
  final bool isDisabled;
  final VoidCallback? onTap;

  const TokenCard({
    super.key,
    required this.token,
    this.balance,
    this.isSelected = false,
    this.isDisabled = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: isDisabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? colorTokens.containerL2
              : colorTokens.containerL1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? colorTokens.strokeHigh
                : colorTokens.strokeLow,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Row(
            children: [
              // Token icon
              _TokenIcon(token: token),
              const SizedBox(width: 12),
              // Token info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      token.displayName,
                      style: typography.paragraphLarge(
                        fontWeight: ArFontWeight.semiBold,
                        color: colorTokens.textHigh,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      token.networkDisplayName,
                      style: typography.paragraphSmall(
                        color: colorTokens.textMid,
                      ),
                    ),
                  ],
                ),
              ),
              // Balance (if available)
              if (balance != null) ...[
                const SizedBox(width: 8),
                _BalanceDisplay(balance: balance!, token: token),
              ],
              // Selection indicator
              if (isSelected) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.check_circle,
                  color: colorTokens.textHigh,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Token icon widget with fallback
class _TokenIcon extends StatelessWidget {
  final CryptoToken token;
  final double size;

  const _TokenIcon({
    required this.token,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    // Map token to icon asset path
    final iconPath = _getTokenIconPath(token);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorTokens.containerL2,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size / 2),
        child: iconPath != null
            ? Image.asset(
                iconPath,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _buildFallbackIcon(context),
              )
            : _buildFallbackIcon(context),
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return Center(
      child: Text(
        token.symbol.substring(0, token.symbol.length > 2 ? 2 : token.symbol.length),
        style: typography.paragraphSmall(
          fontWeight: ArFontWeight.bold,
          color: colorTokens.textHigh,
        ),
      ),
    );
  }

  String? _getTokenIconPath(CryptoToken token) {
    // Token icons are not yet available - use text fallback
    // TODO: Add token icon assets and update paths here
    return null;
  }
}

/// Balance display widget
class _BalanceDisplay extends StatelessWidget {
  final TokenBalance balance;
  final CryptoToken token;

  const _BalanceDisplay({
    required this.balance,
    required this.token,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    if (balance.isLoading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorTokens.textMid,
        ),
      );
    }

    if (balance.hasError) {
      return Icon(
        Icons.error_outline,
        size: 16,
        color: colorTokens.textMid,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          balance.displayBalance,
          style: typography.paragraphNormal(
            fontWeight: ArFontWeight.semiBold,
            color: colorTokens.textHigh,
          ),
        ),
        if (balance.usdValue != null)
          Text(
            '\$${balance.usdValue!.toStringAsFixed(2)}',
            style: typography.paragraphSmall(
              color: colorTokens.textMid,
            ),
          ),
      ],
    );
  }
}

/// A compact version of TokenCard for use in selection lists
class TokenListTile extends StatelessWidget {
  final CryptoToken token;
  final TokenBalance? balance;
  final bool isSelected;
  final VoidCallback? onTap;

  const TokenListTile({
    super.key,
    required this.token,
    this.balance,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return ListTile(
      onTap: onTap,
      leading: _TokenIcon(token: token, size: 32),
      title: Text(
        token.displayName,
        style: typography.paragraphNormal(
          fontWeight: ArFontWeight.semiBold,
          color: colorTokens.textHigh,
        ),
      ),
      subtitle: Text(
        token.networkDisplayName,
        style: typography.paragraphSmall(
          color: colorTokens.textMid,
        ),
      ),
      trailing: isSelected
          ? Icon(
              Icons.check_circle,
              color: colorTokens.textHigh,
            )
          : null,
      selected: isSelected,
      selectedTileColor: colorTokens.containerL2,
    );
  }
}
