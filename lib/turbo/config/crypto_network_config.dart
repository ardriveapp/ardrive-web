import 'package:ardrive/turbo/topup/models/crypto_token.dart';

/// Network configuration for cryptocurrency payments.
///
/// Provides chain IDs, RPC URLs, contract addresses, and explorer URLs
/// for both mainnet and testnet environments.
class CryptoNetworkConfig {
  /// Whether to use testnet configuration
  final bool isTestnet;

  CryptoNetworkConfig({required this.isTestnet});

  /// Factory for creating config based on environment
  ///
  /// - Development: testnet by default (can toggle via debug menu)
  /// - Staging/Production: mainnet
  factory CryptoNetworkConfig.fromEnvironment(String environment) {
    final isTestnet = environment == 'development';
    return CryptoNetworkConfig(isTestnet: isTestnet);
  }

  // ============================================
  // Ethereum L1 Configuration
  // ============================================

  /// Ethereum L1 chain ID (Sepolia testnet or Mainnet)
  int get ethereumChainId => isTestnet ? 11155111 : 1;

  /// Ethereum L1 RPC URL
  String get ethereumRpcUrl => isTestnet
      ? 'https://eth-sepolia.public.blastapi.io'
      : 'https://ethereum.publicnode.com';

  /// Ethereum L1 block explorer URL
  String get ethereumExplorerUrl =>
      isTestnet ? 'https://sepolia.etherscan.io' : 'https://etherscan.io';

  /// Ethereum L1 chain name for display
  String get ethereumChainName => isTestnet ? 'Sepolia' : 'Ethereum Mainnet';

  // ============================================
  // Base L2 Configuration
  // ============================================

  /// Base L2 chain ID (Base Sepolia or Base Mainnet)
  int get baseChainId => isTestnet ? 84532 : 8453;

  /// Base L2 RPC URL
  String get baseRpcUrl =>
      isTestnet ? 'https://sepolia.base.org' : 'https://mainnet.base.org';

  /// Base L2 block explorer URL
  String get baseExplorerUrl =>
      isTestnet ? 'https://sepolia.basescan.org' : 'https://basescan.org';

  /// Base L2 chain name for display
  String get baseChainName => isTestnet ? 'Base Sepolia' : 'Base';

  // ============================================
  // Solana Configuration
  // ============================================

  /// Solana RPC URL
  /// Using QuickNode premium RPC for reliable browser-based requests
  /// (public Solana RPC returns 403 for browser requests)
  String get solanaRpcUrl => isTestnet
      ? 'https://api.devnet.solana.com'
      : 'https://damp-stylish-sheet.solana-mainnet.quiknode.pro/b3dd2ce1c4f1a06d5fb6c42b80d6848796dd6408/';

  /// Solana block explorer URL
  String get solanaExplorerUrl =>
      isTestnet ? 'https://solscan.io?cluster=devnet' : 'https://solscan.io';

  // ============================================
  // Arweave / AO Configuration
  // ============================================

  /// Arweave gateway URL (no testnet distinction)
  String get arweaveGatewayUrl => 'https://arweave.net';

  /// AO gateway URL
  String get aoGatewayUrl => 'https://ao.arweave.net';

  /// AO block explorer URL
  String get aoExplorerUrl => 'https://scan.ar.io';

  // ============================================
  // Contract Addresses
  // ============================================

  /// USDC contract address on Base
  String get usdcBaseAddress => isTestnet
      ? '0x036CbD53842c5426634e7929541eC2318f3dCF7e' // Base Sepolia USDC
      : '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913'; // Base Mainnet USDC

  /// USDC contract address on Ethereum L1
  String get usdcEthAddress => isTestnet
      ? '0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238' // Sepolia USDC
      : '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'; // Mainnet USDC

  /// ARIO contract address on Base
  ///
  /// Testnet address: Contact AR.IO team for Base Sepolia ARIO token address.
  /// For development without testnet ARIO, the token will be disabled.
  ///
  /// Base Sepolia test token faucet: https://docs.ar.io (if available)
  String get arioBaseAddress => isTestnet
      // Base Sepolia ARIO - placeholder until official testnet token deployed
      // Set environment variable ARIO_BASE_TESTNET_ADDRESS to enable in dev
      ? const String.fromEnvironment(
          'ARIO_BASE_TESTNET_ADDRESS',
          defaultValue: '',
        )
      : '0x138746adfA52909E5920def027f5a8dc1C7EfFb6'; // Base Mainnet ARIO

  /// Whether ARIO on Base is available (has contract address configured)
  bool get isArioBaseAvailable => arioBaseAddress.isNotEmpty;

  // ============================================
  // Turbo Service URLs
  // ============================================

  /// Turbo payment service URL
  String get turboPaymentUrl =>
      isTestnet ? 'https://payment.ardrive.dev' : 'https://payment.ardrive.io';

  /// Turbo upload service URL
  String get turboUploadUrl =>
      isTestnet ? 'https://upload.ardrive.dev' : 'https://upload.ardrive.io';

  // ============================================
  // Helper Methods
  // ============================================

  /// Get the chain ID for a specific token
  int? getChainIdForToken(CryptoToken token) {
    return switch (token) {
      CryptoToken.arioBase ||
      CryptoToken.usdcBase ||
      CryptoToken.ethBase =>
        baseChainId,
      CryptoToken.usdcEth || CryptoToken.ethL1 => ethereumChainId,
      _ => null, // Non-EVM tokens
    };
  }

  /// Get the RPC URL for a specific token
  String? getRpcUrlForToken(CryptoToken token) {
    return switch (token) {
      CryptoToken.arioBase ||
      CryptoToken.usdcBase ||
      CryptoToken.ethBase =>
        baseRpcUrl,
      CryptoToken.usdcEth || CryptoToken.ethL1 => ethereumRpcUrl,
      CryptoToken.sol => solanaRpcUrl,
      CryptoToken.arioAO || CryptoToken.arioAOViaEth => arweaveGatewayUrl,
    };
  }

  /// Get the block explorer URL for a transaction
  String getExplorerTxUrl(CryptoToken token, String txId) {
    return switch (token) {
      CryptoToken.arioAO ||
      CryptoToken.arioAOViaEth =>
        'https://scan.ar.io/#/message/$txId',
      CryptoToken.arioBase ||
      CryptoToken.usdcBase ||
      CryptoToken.ethBase =>
        '$baseExplorerUrl/tx/$txId',
      CryptoToken.usdcEth ||
      CryptoToken.ethL1 =>
        '$ethereumExplorerUrl/tx/$txId',
      CryptoToken.sol => isTestnet
          ? '$solanaExplorerUrl/tx/$txId'
          : 'https://solscan.io/tx/$txId',
    };
  }

  /// Get the contract address for a token (if applicable)
  String? getContractAddressForToken(CryptoToken token) {
    return switch (token) {
      CryptoToken.usdcBase => usdcBaseAddress,
      CryptoToken.usdcEth => usdcEthAddress,
      CryptoToken.arioBase =>
        arioBaseAddress.isNotEmpty ? arioBaseAddress : null,
      _ => null, // Native tokens or non-EVM
    };
  }

  /// Get EIP-3085 parameters for adding a network to a wallet
  Map<String, dynamic> getAddNetworkParams(CryptoToken token) {
    final chainId = getChainIdForToken(token);
    if (chainId == null) {
      throw ArgumentError('Token $token does not have an EVM chain');
    }

    // Only Base is typically missing from wallets
    if (token == CryptoToken.arioBase ||
        token == CryptoToken.usdcBase ||
        token == CryptoToken.ethBase) {
      return {
        'chainId': '0x${chainId.toRadixString(16)}',
        'chainName': baseChainName,
        'nativeCurrency': {
          'name': 'Ethereum',
          'symbol': 'ETH',
          'decimals': 18,
        },
        'rpcUrls': [baseRpcUrl],
        'blockExplorerUrls': [baseExplorerUrl],
      };
    }

    // Ethereum mainnet/Sepolia - should already be in wallets
    return {
      'chainId': '0x${chainId.toRadixString(16)}',
      'chainName': ethereumChainName,
      'nativeCurrency': {
        'name': 'Ethereum',
        'symbol': 'ETH',
        'decimals': 18,
      },
      'rpcUrls': [ethereumRpcUrl],
      'blockExplorerUrls': [ethereumExplorerUrl],
    };
  }

  /// Get display-friendly chain name for a token
  String getChainDisplayName(CryptoToken token) {
    return switch (token) {
      CryptoToken.arioAO || CryptoToken.arioAOViaEth => 'AO',
      CryptoToken.arioBase ||
      CryptoToken.usdcBase ||
      CryptoToken.ethBase =>
        baseChainName,
      CryptoToken.usdcEth || CryptoToken.ethL1 => ethereumChainName,
      CryptoToken.sol => isTestnet ? 'Solana Devnet' : 'Solana',
    };
  }

  @override
  String toString() {
    return 'CryptoNetworkConfig{isTestnet: $isTestnet}';
  }
}

/// ERC-20 ABI for balance queries
const erc20BalanceOfAbi = [
  {
    'constant': true,
    'inputs': [
      {'name': 'owner', 'type': 'address'}
    ],
    'name': 'balanceOf',
    'outputs': [
      {'name': '', 'type': 'uint256'}
    ],
    'type': 'function',
  },
];

/// Minimal ERC-20 ABI string for JS interop
const erc20AbiString = '''[
  "function balanceOf(address owner) view returns (uint256)"
]''';
