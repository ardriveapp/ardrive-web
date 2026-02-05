import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// A RainbowKit-style wallet selector modal that shows all available wallets.
///
/// This modal detects available wallet providers and displays them in a
/// grid layout, allowing users to select their preferred wallet.
class WalletSelectorModal extends StatelessWidget {
  final WalletType walletType;
  final List<DetectedWallet> detectedWallets;
  final bool isConnecting;
  final String? connectingWalletId;
  final ValueChanged<DetectedWallet> onWalletSelected;
  final VoidCallback? onClose;

  const WalletSelectorModal({
    super.key,
    required this.walletType,
    required this.detectedWallets,
    required this.onWalletSelected,
    this.isConnecting = false,
    this.connectingWalletId,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.themeBgSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.themeBorderDefault),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Connect Wallet',
                style: typography.heading5(
                  fontWeight: ArFontWeight.bold,
                  color: colors.themeFgDefault,
                ),
              ),
              if (onClose != null)
                IconButton(
                  onPressed: onClose,
                  icon: Icon(
                    Icons.close,
                    color: colors.themeFgMuted,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _getSubtitle(),
            style: typography.paragraphSmall(
              color: colors.themeFgMuted,
            ),
          ),
          const SizedBox(height: 20),

          // Wallet grid
          if (detectedWallets.isEmpty)
            _buildNoWalletsMessage(context, colors, typography)
          else
            _buildWalletGrid(context, colors, typography),

          // Help text
          const SizedBox(height: 16),
          Center(
            child: Text(
              _getHelpText(),
              style: typography.caption(
                color: colors.themeFgMuted,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  String _getSubtitle() {
    return switch (walletType) {
      WalletType.ethereum => 'Choose your preferred Ethereum wallet',
      WalletType.solana => 'Choose your preferred Solana wallet',
      WalletType.arweave => 'Connect with ArConnect',
    };
  }

  String _getHelpText() {
    return switch (walletType) {
      WalletType.ethereum => 'New to Ethereum wallets? Get MetaMask',
      WalletType.solana => 'New to Solana wallets? Get Phantom',
      WalletType.arweave => 'ArConnect is required for Arweave transactions',
    };
  }

  Widget _buildNoWalletsMessage(
    BuildContext context,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.themeWarningSubtle,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colors.themeWarningFg,
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'No wallets detected',
            style: typography.paragraphNormal(
              fontWeight: ArFontWeight.semiBold,
              color: colors.themeWarningFg,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _getInstallMessage(),
            style: typography.paragraphSmall(
              color: colors.themeFgMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  String _getInstallMessage() {
    return switch (walletType) {
      WalletType.ethereum =>
        'Please install a wallet extension like MetaMask, Coinbase Wallet, or Rainbow to continue.',
      WalletType.solana => 'Please install Phantom or Solflare to continue.',
      WalletType.arweave => 'Please install ArConnect to continue.',
    };
  }

  Widget _buildWalletGrid(
    BuildContext context,
    ArDriveColors colors,
    ArdriveTypographyNew typography,
  ) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
      ),
      itemCount: detectedWallets.length,
      itemBuilder: (context, index) {
        final wallet = detectedWallets[index];
        final isThisConnecting =
            isConnecting && connectingWalletId == wallet.id;

        return _WalletCard(
          wallet: wallet,
          isConnecting: isThisConnecting,
          isDisabled: isConnecting && !isThisConnecting,
          onTap: () => onWalletSelected(wallet),
        );
      },
    );
  }
}

/// Individual wallet card in the grid
class _WalletCard extends StatelessWidget {
  final DetectedWallet wallet;
  final bool isConnecting;
  final bool isDisabled;
  final VoidCallback onTap;

  const _WalletCard({
    required this.wallet,
    required this.isConnecting,
    required this.isDisabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colors;
    final typography = ArDriveTypographyNew.of(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDisabled
                ? colors.themeBgSubtle.withOpacity(0.5)
                : colors.themeBgSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isConnecting
                  ? colors.themeFgDefault
                  : colors.themeBorderDefault,
              width: isConnecting ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Wallet icon
              if (isConnecting)
                SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colors.themeFgDefault,
                  ),
                )
              else
                _WalletIcon(
                  wallet: wallet,
                  size: 32,
                  colors: colors,
                ),
              const SizedBox(height: 8),
              // Wallet name
              Text(
                wallet.displayName,
                style: typography.paragraphSmall(
                  fontWeight: ArFontWeight.semiBold,
                  color:
                      isDisabled ? colors.themeFgMuted : colors.themeFgDefault,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              // Status text
              if (isConnecting)
                Text(
                  'Connecting...',
                  style: typography.caption(
                    color: colors.themeFgMuted,
                  ),
                )
              else if (wallet.isInstalled)
                Text(
                  'Detected',
                  style: typography.caption(
                    color: colors.themeSuccessDefault,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Wallet icon widget
class _WalletIcon extends StatelessWidget {
  final DetectedWallet wallet;
  final double size;
  final ArDriveColors colors;

  const _WalletIcon({
    required this.wallet,
    required this.size,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Use colored circle with wallet initial as fallback
    // In production, you'd want actual wallet logos
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _getWalletColor(),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          wallet.displayName.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Color _getWalletColor() {
    switch (wallet.id) {
      case 'metamask':
        return const Color(0xFFE2761B); // MetaMask orange
      case 'coinbase':
        return const Color(0xFF0052FF); // Coinbase blue
      case 'rainbow':
        return const Color(0xFF001E59); // Rainbow dark blue
      case 'trust':
        return const Color(0xFF3375BB); // Trust blue
      case 'brave':
        return const Color(0xFFFF5500); // Brave orange
      case 'phantom':
        return const Color(0xFFAB9FF2); // Phantom purple
      case 'solflare':
        return const Color(0xFFFC8C03); // Solflare orange
      case 'arconnect':
        return const Color(0xFF1A1A1A); // ArConnect dark
      case 'walletconnect':
        return const Color(0xFF3B99FC); // WalletConnect blue
      default:
        return colors.themeFgMuted;
    }
  }
}

/// Represents a detected wallet provider
class DetectedWallet {
  final String id;
  final String displayName;
  final bool isInstalled;
  final EthereumWalletProvider? ethereumProvider;
  final SolanaWalletProvider? solanaProvider;

  const DetectedWallet({
    required this.id,
    required this.displayName,
    this.isInstalled = false,
    this.ethereumProvider,
    this.solanaProvider,
  });

  /// Create list of detected Ethereum wallets
  static List<DetectedWallet> fromEthereumDetection({
    required bool hasMetaMask,
    required bool hasCoinbase,
    required bool hasRainbow,
    required bool hasTrust,
    required bool hasBrave,
  }) {
    final wallets = <DetectedWallet>[];

    // Add detected wallets first
    if (hasMetaMask) {
      wallets.add(const DetectedWallet(
        id: 'metamask',
        displayName: 'MetaMask',
        isInstalled: true,
        ethereumProvider: EthereumWalletProvider.metamask,
      ));
    }
    if (hasCoinbase) {
      wallets.add(const DetectedWallet(
        id: 'coinbase',
        displayName: 'Coinbase',
        isInstalled: true,
        ethereumProvider: EthereumWalletProvider.coinbaseWallet,
      ));
    }
    if (hasRainbow) {
      wallets.add(const DetectedWallet(
        id: 'rainbow',
        displayName: 'Rainbow',
        isInstalled: true,
        ethereumProvider: EthereumWalletProvider.rainbow,
      ));
    }
    if (hasTrust) {
      wallets.add(const DetectedWallet(
        id: 'trust',
        displayName: 'Trust Wallet',
        isInstalled: true,
      ));
    }
    if (hasBrave) {
      wallets.add(const DetectedWallet(
        id: 'brave',
        displayName: 'Brave',
        isInstalled: true,
      ));
    }

    // Always show WalletConnect as an option for mobile
    wallets.add(const DetectedWallet(
      id: 'walletconnect',
      displayName: 'WalletConnect',
      isInstalled: true, // Always available
      ethereumProvider: EthereumWalletProvider.walletConnect,
    ));

    // If no wallets detected, show popular options
    if (wallets.length == 1) {
      // Only WalletConnect
      wallets.insertAll(0, [
        const DetectedWallet(
          id: 'metamask',
          displayName: 'MetaMask',
          isInstalled: false,
          ethereumProvider: EthereumWalletProvider.metamask,
        ),
        const DetectedWallet(
          id: 'coinbase',
          displayName: 'Coinbase',
          isInstalled: false,
          ethereumProvider: EthereumWalletProvider.coinbaseWallet,
        ),
      ]);
    }

    return wallets;
  }

  /// Create list of detected Solana wallets
  static List<DetectedWallet> fromSolanaDetection({
    required bool hasPhantom,
    required bool hasSolflare,
  }) {
    final wallets = <DetectedWallet>[];

    if (hasPhantom) {
      wallets.add(const DetectedWallet(
        id: 'phantom',
        displayName: 'Phantom',
        isInstalled: true,
        solanaProvider: SolanaWalletProvider.phantom,
      ));
    }
    if (hasSolflare) {
      wallets.add(const DetectedWallet(
        id: 'solflare',
        displayName: 'Solflare',
        isInstalled: true,
        solanaProvider: SolanaWalletProvider.solflare,
      ));
    }

    // If no wallets detected, show options
    if (wallets.isEmpty) {
      wallets.addAll([
        const DetectedWallet(
          id: 'phantom',
          displayName: 'Phantom',
          isInstalled: false,
          solanaProvider: SolanaWalletProvider.phantom,
        ),
        const DetectedWallet(
          id: 'solflare',
          displayName: 'Solflare',
          isInstalled: false,
          solanaProvider: SolanaWalletProvider.solflare,
        ),
      ]);
    }

    return wallets;
  }
}

/// Shows the wallet selector as a modal dialog
Future<DetectedWallet?> showWalletSelectorModal(
  BuildContext context, {
  required WalletType walletType,
  required List<DetectedWallet> detectedWallets,
}) async {
  return showDialog<DetectedWallet>(
    context: context,
    barrierDismissible: true,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: WalletSelectorModal(
          walletType: walletType,
          detectedWallets: detectedWallets,
          onWalletSelected: (wallet) {
            Navigator.of(context).pop(wallet);
          },
          onClose: () => Navigator.of(context).pop(),
        ),
      ),
    ),
  );
}
