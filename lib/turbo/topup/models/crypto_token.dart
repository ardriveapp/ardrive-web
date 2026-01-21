import 'package:equatable/equatable.dart';

/// Supported cryptocurrency tokens for Turbo top-up payments.
///
/// Ordered by priority (fastest/cheapest first):
/// 1. ARIO on AO - instant, uses existing Arweave wallet
/// 2. ARIO on AO via ETH - instant, requires one-time signature
/// 3. ARIO on Base - ~3 min, low fees
/// 4. SOL - ~2 min, low fees
/// 5. USDC on Base - ~3 min, stablecoin
/// 6. ETH on Base - ~3 min, low fees
/// 7. USDC on Ethereum L1 - ~15 min, higher fees
/// 8. ETH on Ethereum L1 - ~15 min, higher fees
/// Blockchain/network type
enum Blockchain {
  ao,
  ethereum,
  base,
  solana,
}

enum CryptoToken {
  /// ARIO on AO network using the user's Arweave wallet (already connected)
  arioAO,

  /// ARIO on AO network using an Ethereum wallet (requires InjectedEthereumSigner)
  arioAOViaEth,

  /// ARIO on Base L2 (ERC-20)
  arioBase,

  /// SOL on Solana
  sol,

  /// USDC on Base L2 (ERC-20)
  usdcBase,

  /// ETH on Base L2 (native)
  ethBase,

  /// USDC on Ethereum L1 (ERC-20)
  usdcEth,

  /// ETH on Ethereum L1 (native)
  ethL1,
}

/// The type of wallet required for a token
enum WalletType {
  arweave,
  ethereum,
  solana,
}

/// Extension methods for WalletType
extension WalletTypeX on WalletType {
  /// Display name for the wallet type
  String get displayName => switch (this) {
        WalletType.arweave => 'Arweave Wallet',
        WalletType.ethereum => 'Ethereum Wallet',
        WalletType.solana => 'Solana Wallet',
      };

  /// Install URL for the wallet type
  String get installUrl => switch (this) {
        WalletType.arweave => 'https://www.arconnect.io/download',
        WalletType.ethereum => 'https://metamask.io/download/',
        WalletType.solana => 'https://phantom.app/download',
      };
}

/// Extension methods for [CryptoToken]
extension CryptoTokenX on CryptoToken {
  /// Display name for the token (shown in UI)
  String get displayName => switch (this) {
        CryptoToken.arioAO => 'ARIO on AO',
        CryptoToken.arioAOViaEth => 'ARIO on AO (via Ethereum wallet)',
        CryptoToken.arioBase => 'ARIO on Base',
        CryptoToken.sol => 'SOL',
        CryptoToken.usdcBase => 'USDC on Base',
        CryptoToken.ethBase => 'ETH on Base',
        CryptoToken.usdcEth => 'USDC on Ethereum',
        CryptoToken.ethL1 => 'ETH on Ethereum',
      };

  /// Token symbol (e.g., "ARIO", "ETH", "SOL")
  String get symbol => switch (this) {
        CryptoToken.arioAO ||
        CryptoToken.arioAOViaEth ||
        CryptoToken.arioBase =>
          'ARIO',
        CryptoToken.sol => 'SOL',
        CryptoToken.usdcBase || CryptoToken.usdcEth => 'USDC',
        CryptoToken.ethBase || CryptoToken.ethL1 => 'ETH',
      };

  /// Chain/network name
  String get chain => switch (this) {
        CryptoToken.arioAO || CryptoToken.arioAOViaEth => 'AO',
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          'Base',
        CryptoToken.sol => 'Solana',
        CryptoToken.usdcEth || CryptoToken.ethL1 => 'Ethereum',
      };

  /// Blockchain enum value
  Blockchain get blockchain => switch (this) {
        CryptoToken.arioAO || CryptoToken.arioAOViaEth => Blockchain.ao,
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          Blockchain.base,
        CryptoToken.sol => Blockchain.solana,
        CryptoToken.usdcEth || CryptoToken.ethL1 => Blockchain.ethereum,
      };

  /// Network display name for UI
  String get networkDisplayName => switch (this) {
        CryptoToken.arioAO || CryptoToken.arioAOViaEth => 'AO Network',
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          'Base (L2)',
        CryptoToken.sol => 'Solana',
        CryptoToken.usdcEth || CryptoToken.ethL1 => 'Ethereum (L1)',
      };

  /// Number of decimal places for the token
  int get decimals => switch (this) {
        CryptoToken.arioAO ||
        CryptoToken.arioAOViaEth ||
        CryptoToken.arioBase =>
          6, // mARIO
        CryptoToken.sol => 9, // lamports
        CryptoToken.usdcBase || CryptoToken.usdcEth => 6, // USDC standard
        CryptoToken.ethBase || CryptoToken.ethL1 => 18, // wei
      };

  /// EVM chain ID (null for non-EVM tokens)
  int? get chainId => switch (this) {
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          8453, // Base Mainnet
        CryptoToken.usdcEth || CryptoToken.ethL1 => 1, // Ethereum Mainnet
        _ => null, // arioAO, arioAOViaEth, sol don't have EVM chain IDs
      };

  /// EVM chain ID for testnet (null for non-EVM tokens)
  int? get testnetChainId => switch (this) {
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          84532, // Base Sepolia
        CryptoToken.usdcEth || CryptoToken.ethL1 => 11155111, // Sepolia
        _ => null,
      };

  /// The type of wallet required to pay with this token
  WalletType get walletType => switch (this) {
        CryptoToken.arioAO => WalletType.arweave,
        CryptoToken.arioAOViaEth ||
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase ||
        CryptoToken.usdcEth ||
        CryptoToken.ethL1 =>
          WalletType.ethereum,
        CryptoToken.sol => WalletType.solana,
      };

  /// Estimated confirmation time
  Duration get estimatedConfirmationTime => switch (this) {
        CryptoToken.arioAO ||
        CryptoToken.arioAOViaEth ||
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          const Duration(minutes: 3),
        CryptoToken.sol => const Duration(minutes: 2),
        CryptoToken.usdcEth || CryptoToken.ethL1 => const Duration(minutes: 15),
      };

  /// Human-readable confirmation time string
  String get confirmationTimeText => switch (this) {
        CryptoToken.arioAO => 'Instant',
        CryptoToken.arioAOViaEth => 'Instant',
        CryptoToken.arioBase ||
        CryptoToken.usdcBase ||
        CryptoToken.ethBase =>
          '~3 min',
        CryptoToken.sol => '~2 min',
        CryptoToken.usdcEth || CryptoToken.ethL1 => '~15 min',
      };

  /// Description shown below the token name
  String get description => switch (this) {
        CryptoToken.arioAO => 'Instant · Uses your ArDrive wallet',
        CryptoToken.arioAOViaEth => 'Instant · Requires one-time signature',
        CryptoToken.arioBase => '~3 min · Low gas fees',
        CryptoToken.sol => '~2 min · Low fees',
        CryptoToken.usdcBase => '~3 min · Stablecoin',
        CryptoToken.ethBase => '~3 min · Low fees',
        CryptoToken.usdcEth => '~15 min · Higher fees',
        CryptoToken.ethL1 => '~15 min · Higher fees',
      };

  /// Whether this is a fast token (≤5 min confirmation)
  bool get isFast => estimatedConfirmationTime.inMinutes <= 5;

  /// Whether this token requires the AO connect signature flow
  bool get requiresAOConnectSignature => this == CryptoToken.arioAOViaEth;

  /// Whether this is a native token (not ERC-20)
  bool get isNativeToken => switch (this) {
        CryptoToken.ethBase || CryptoToken.ethL1 || CryptoToken.sol => true,
        _ => false,
      };

  /// Whether this is an ERC-20 token
  bool get isERC20 => switch (this) {
        CryptoToken.arioBase || CryptoToken.usdcBase || CryptoToken.usdcEth =>
          true,
        _ => false,
      };

  /// Whether this token uses the AO network
  bool get isAOToken =>
      this == CryptoToken.arioAO || this == CryptoToken.arioAOViaEth;

  /// Whether gas estimation is needed (for EVM native token payments)
  bool get requiresGasEstimation => switch (this) {
        CryptoToken.ethBase ||
        CryptoToken.ethL1 ||
        CryptoToken.usdcBase ||
        CryptoToken.usdcEth ||
        CryptoToken.arioBase =>
          true,
        CryptoToken.sol => true,
        CryptoToken.arioAO || CryptoToken.arioAOViaEth => false,
      };

  /// Token type string for Turbo SDK API calls
  String get turboTokenType => switch (this) {
        CryptoToken.arioAO => 'ario',
        CryptoToken.arioAOViaEth => 'ario',
        CryptoToken.arioBase => 'base-ario',
        CryptoToken.sol => 'solana',
        CryptoToken.usdcBase => 'base-usdc',
        CryptoToken.ethBase => 'base-eth',
        CryptoToken.usdcEth => 'usdc',
        CryptoToken.ethL1 => 'ethereum',
      };
}

/// Groups tokens by their wallet requirement for UI display
class TokenGroup extends Equatable {
  final String? label;
  final List<CryptoToken> tokens;

  const TokenGroup({
    this.label,
    required this.tokens,
  });

  @override
  List<Object?> get props => [label, tokens];

  /// Get all token groups for display in the token selection view
  static List<TokenGroup> get allGroups => [
        // Arweave wallet tokens (no label needed - uses existing wallet)
        const TokenGroup(
          tokens: [CryptoToken.arioAO],
        ),
        // Ethereum wallet tokens
        const TokenGroup(
          label: 'Requires Ethereum Wallet',
          tokens: [
            CryptoToken.arioAOViaEth,
            CryptoToken.arioBase,
            CryptoToken.usdcBase,
            CryptoToken.ethBase,
            CryptoToken.usdcEth,
            CryptoToken.ethL1,
          ],
        ),
        // Solana wallet tokens
        const TokenGroup(
          label: 'Requires Solana Wallet',
          tokens: [CryptoToken.sol],
        ),
      ];
}
