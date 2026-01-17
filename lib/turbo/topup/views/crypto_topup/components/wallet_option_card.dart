import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// UI-specific wallet provider enum for display purposes
enum UIWalletProvider {
  metamask,
  coinbase,
  phantom,
  solflare,
  arconnect,
}

extension UIWalletProviderExtension on UIWalletProvider {
  String get displayName {
    switch (this) {
      case UIWalletProvider.metamask:
        return 'MetaMask';
      case UIWalletProvider.coinbase:
        return 'Coinbase Wallet';
      case UIWalletProvider.phantom:
        return 'Phantom';
      case UIWalletProvider.solflare:
        return 'Solflare';
      case UIWalletProvider.arconnect:
        return 'ArConnect';
    }
  }

  String get description {
    switch (this) {
      case UIWalletProvider.metamask:
        return 'Connect with MetaMask browser extension';
      case UIWalletProvider.coinbase:
        return 'Connect with Coinbase Wallet';
      case UIWalletProvider.phantom:
        return 'Connect with Phantom wallet';
      case UIWalletProvider.solflare:
        return 'Connect with Solflare wallet';
      case UIWalletProvider.arconnect:
        return 'Connect with ArConnect wallet';
    }
  }

  String? get iconPath {
    // TODO: Add wallet icon assets when available
    // For now, return null to use text fallback icons
    switch (this) {
      case UIWalletProvider.metamask:
      case UIWalletProvider.coinbase:
      case UIWalletProvider.phantom:
      case UIWalletProvider.solflare:
      case UIWalletProvider.arconnect:
        return null; // Use fallback icon
    }
  }

  String get installUrl {
    switch (this) {
      case UIWalletProvider.metamask:
        return 'https://metamask.io/download/';
      case UIWalletProvider.coinbase:
        return 'https://www.coinbase.com/wallet/downloads';
      case UIWalletProvider.phantom:
        return 'https://phantom.app/download';
      case UIWalletProvider.solflare:
        return 'https://solflare.com/download';
      case UIWalletProvider.arconnect:
        return 'https://www.arconnect.io/download';
    }
  }

  /// Get the WalletType for this UI provider
  WalletType get walletType {
    switch (this) {
      case UIWalletProvider.metamask:
      case UIWalletProvider.coinbase:
        return WalletType.ethereum;
      case UIWalletProvider.phantom:
      case UIWalletProvider.solflare:
        return WalletType.solana;
      case UIWalletProvider.arconnect:
        return WalletType.arweave;
    }
  }

  /// Get the EthereumWalletProvider for this UI provider (if applicable)
  EthereumWalletProvider? get ethereumProvider {
    switch (this) {
      case UIWalletProvider.metamask:
        return EthereumWalletProvider.metamask;
      case UIWalletProvider.coinbase:
        return EthereumWalletProvider.coinbaseWallet;
      case UIWalletProvider.phantom:
      case UIWalletProvider.solflare:
      case UIWalletProvider.arconnect:
        return null;
    }
  }

  /// Get the SolanaWalletProvider for this UI provider (if applicable)
  SolanaWalletProvider? get solanaProvider {
    switch (this) {
      case UIWalletProvider.phantom:
        return SolanaWalletProvider.phantom;
      case UIWalletProvider.solflare:
        return SolanaWalletProvider.solflare;
      case UIWalletProvider.metamask:
      case UIWalletProvider.coinbase:
      case UIWalletProvider.arconnect:
        return null;
    }
  }
}

/// Get UI wallet providers for a given wallet type
List<UIWalletProvider> getUIWalletProviders(WalletType walletType) {
  switch (walletType) {
    case WalletType.ethereum:
      return [UIWalletProvider.metamask, UIWalletProvider.coinbase];
    case WalletType.solana:
      return [UIWalletProvider.phantom, UIWalletProvider.solflare];
    case WalletType.arweave:
      return [UIWalletProvider.arconnect];
  }
}

/// A card widget for selecting a wallet provider.
class WalletOptionCard extends StatelessWidget {
  final UIWalletProvider provider;
  final bool isAvailable;
  final bool isConnecting;
  final bool isConnected;
  final String? connectedAddress;
  final VoidCallback? onTap;
  final VoidCallback? onInstallTap;

  const WalletOptionCard({
    super.key,
    required this.provider,
    this.isAvailable = true,
    this.isConnecting = false,
    this.isConnected = false,
    this.connectedAddress,
    this.onTap,
    this.onInstallTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    return GestureDetector(
      onTap: isConnecting ? null : (isAvailable ? onTap : onInstallTap),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isConnected
              ? colorTokens.containerL2
              : colorTokens.containerL1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isConnected
                ? colorTokens.strokeHigh
                : colorTokens.strokeLow,
            width: isConnected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Wallet icon
            _WalletIcon(provider: provider, isAvailable: isAvailable),
            const SizedBox(width: 12),
            // Wallet info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    provider.displayName,
                    style: typography.paragraphLarge(
                      fontWeight: ArFontWeight.semiBold,
                      color: isAvailable
                          ? colorTokens.textHigh
                          : colorTokens.textMid,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (isConnected && connectedAddress != null)
                    Text(
                      _truncateAddress(connectedAddress!),
                      style: typography.paragraphSmall(
                        color: colorTokens.textMid,
                      ),
                    )
                  else if (!isAvailable)
                    Text(
                      'Not installed - Click to install',
                      style: typography.paragraphSmall(
                        color: colorTokens.textLow,
                      ),
                    )
                  else
                    Text(
                      provider.description,
                      style: typography.paragraphSmall(
                        color: colorTokens.textMid,
                      ),
                    ),
                ],
              ),
            ),
            // Status indicator
            _buildStatusIndicator(context, colorTokens),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(
    BuildContext context,
    ArDriveColorTokens colorTokens,
  ) {
    if (isConnecting) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colorTokens.textMid,
        ),
      );
    }

    if (isConnected) {
      return Icon(
        Icons.check_circle,
        color: colorTokens.textHigh,
        size: 20,
      );
    }

    if (!isAvailable) {
      return Icon(
        Icons.download,
        color: colorTokens.textMid,
        size: 20,
      );
    }

    return Icon(
      Icons.arrow_forward_ios,
      color: colorTokens.textMid,
      size: 16,
    );
  }

  String _truncateAddress(String address) {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }
}

/// Wallet icon widget with fallback
class _WalletIcon extends StatelessWidget {
  final UIWalletProvider provider;
  final bool isAvailable;

  static const double _iconSize = 40;

  const _WalletIcon({
    required this.provider,
    this.isAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;

    return Opacity(
      opacity: isAvailable ? 1.0 : 0.5,
      child: Container(
        width: _iconSize,
        height: _iconSize,
        decoration: BoxDecoration(
          color: colorTokens.containerL2,
          borderRadius: BorderRadius.circular(_iconSize / 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_iconSize / 2),
          child: provider.iconPath != null
              ? Image.asset(
                  provider.iconPath!,
                  width: _iconSize,
                  height: _iconSize,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _buildFallbackIcon(context),
                )
              : _buildFallbackIcon(context),
        ),
      ),
    );
  }

  Widget _buildFallbackIcon(BuildContext context) {
    final colorTokens = ArDriveTheme.of(context).themeData.colorTokens;
    final typography = ArDriveTypographyNew.of(context);

    // Show wallet initials as fallback
    final initials = _getWalletInitials(provider);

    return Center(
      child: Text(
        initials,
        style: typography.paragraphNormal(
          fontWeight: ArFontWeight.bold,
          color: colorTokens.textHigh,
        ),
      ),
    );
  }

  String _getWalletInitials(UIWalletProvider provider) {
    switch (provider) {
      case UIWalletProvider.metamask:
        return 'MM';
      case UIWalletProvider.coinbase:
        return 'CB';
      case UIWalletProvider.phantom:
        return 'PH';
      case UIWalletProvider.solflare:
        return 'SF';
      case UIWalletProvider.arconnect:
        return 'AC';
    }
  }
}

/// A list of available wallet options for a specific blockchain
class WalletOptionsList extends StatelessWidget {
  final List<WalletOptionData> wallets;
  final UIWalletProvider? connectingWallet;
  final UIWalletProvider? connectedWallet;
  final String? connectedAddress;
  final void Function(UIWalletProvider provider)? onWalletTap;
  final void Function(UIWalletProvider provider)? onInstallTap;

  const WalletOptionsList({
    super.key,
    required this.wallets,
    this.connectingWallet,
    this.connectedWallet,
    this.connectedAddress,
    this.onWalletTap,
    this.onInstallTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: wallets.map((wallet) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: WalletOptionCard(
            provider: wallet.provider,
            isAvailable: wallet.isAvailable,
            isConnecting: connectingWallet == wallet.provider,
            isConnected: connectedWallet == wallet.provider,
            connectedAddress:
                connectedWallet == wallet.provider ? connectedAddress : null,
            onTap: onWalletTap != null ? () => onWalletTap!(wallet.provider) : null,
            onInstallTap:
                onInstallTap != null ? () => onInstallTap!(wallet.provider) : null,
          ),
        );
      }).toList(),
    );
  }
}

/// Data class for wallet option configuration
class WalletOptionData {
  final UIWalletProvider provider;
  final bool isAvailable;

  const WalletOptionData({
    required this.provider,
    this.isAvailable = true,
  });
}
