import 'package:ardrive/turbo/topup/models/wallet_connection_state.dart';

/// A wallet the browser has, or one worth offering when it has none.
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
