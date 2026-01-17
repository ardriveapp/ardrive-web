import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:equatable/equatable.dart';

/// Supported Ethereum wallet providers
enum EthereumWalletProvider {
  metamask,
  rainbow,
  walletConnect,
  coinbaseWallet,
}

/// Extension methods for [EthereumWalletProvider]
extension EthereumWalletProviderX on EthereumWalletProvider {
  String get displayName => switch (this) {
        EthereumWalletProvider.metamask => 'MetaMask',
        EthereumWalletProvider.rainbow => 'Rainbow',
        EthereumWalletProvider.walletConnect => 'WalletConnect',
        EthereumWalletProvider.coinbaseWallet => 'Coinbase Wallet',
      };

  String get description => switch (this) {
        EthereumWalletProvider.metamask => 'Browser extension',
        EthereumWalletProvider.rainbow => 'Mobile & browser',
        EthereumWalletProvider.walletConnect => 'Connect mobile wallet',
        EthereumWalletProvider.coinbaseWallet => 'Browser & mobile',
      };

  String get installUrl => switch (this) {
        EthereumWalletProvider.metamask => 'https://metamask.io/download/',
        EthereumWalletProvider.rainbow => 'https://rainbow.me/',
        EthereumWalletProvider.walletConnect => 'https://walletconnect.com/',
        EthereumWalletProvider.coinbaseWallet =>
          'https://www.coinbase.com/wallet',
      };

  /// Icon asset path
  String get iconAsset => switch (this) {
        EthereumWalletProvider.metamask =>
          'assets/images/icons/metamask_logo.svg',
        EthereumWalletProvider.rainbow => 'assets/images/icons/rainbow_logo.svg',
        EthereumWalletProvider.walletConnect =>
          'assets/images/icons/walletconnect_logo.svg',
        EthereumWalletProvider.coinbaseWallet =>
          'assets/images/icons/coinbase_wallet_logo.svg',
      };
}

/// Supported Solana wallet providers
enum SolanaWalletProvider {
  phantom,
  solflare,
}

/// Extension methods for [SolanaWalletProvider]
extension SolanaWalletProviderX on SolanaWalletProvider {
  String get displayName => switch (this) {
        SolanaWalletProvider.phantom => 'Phantom',
        SolanaWalletProvider.solflare => 'Solflare',
      };

  String get description => switch (this) {
        SolanaWalletProvider.phantom => 'Most popular Solana wallet',
        SolanaWalletProvider.solflare => 'Browser & mobile',
      };

  String get installUrl => switch (this) {
        SolanaWalletProvider.phantom => 'https://phantom.app/download',
        SolanaWalletProvider.solflare => 'https://solflare.com/',
      };

  /// Icon asset path
  String get iconAsset => switch (this) {
        SolanaWalletProvider.phantom => 'assets/images/icons/phantom_logo.svg',
        SolanaWalletProvider.solflare =>
          'assets/images/icons/solflare_logo.svg',
      };
}

/// State of a connected Ethereum wallet
class EthereumWalletState extends Equatable {
  /// Wallet address (0x...)
  final String address;

  /// Current chain ID
  final int chainId;

  /// Which provider is connected
  final EthereumWalletProvider provider;

  /// Balance in native token (wei)
  final BigInt? nativeBalance;

  /// Whether the AO connect signature has been obtained (for ARIO via ETH)
  final bool hasAOSignature;

  const EthereumWalletState({
    required this.address,
    required this.chainId,
    required this.provider,
    this.nativeBalance,
    this.hasAOSignature = false,
  });

  /// Truncated address for display (0x1234...5678)
  String get truncatedAddress {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  /// Display name with provider
  String get displayWithProvider => '$truncatedAddress (${provider.displayName})';

  /// Whether the wallet is on the correct chain for the given token
  bool isCorrectChainFor(CryptoToken token, {required bool isTestnet}) {
    final expectedChainId = isTestnet ? token.testnetChainId : token.chainId;
    if (expectedChainId == null) return true; // Non-EVM tokens
    return chainId == expectedChainId;
  }

  /// Human-readable chain name
  String get chainName => switch (chainId) {
        1 => 'Ethereum Mainnet',
        11155111 => 'Sepolia',
        8453 => 'Base',
        84532 => 'Base Sepolia',
        _ => 'Chain $chainId',
      };

  EthereumWalletState copyWith({
    String? address,
    int? chainId,
    EthereumWalletProvider? provider,
    BigInt? nativeBalance,
    bool? hasAOSignature,
  }) {
    return EthereumWalletState(
      address: address ?? this.address,
      chainId: chainId ?? this.chainId,
      provider: provider ?? this.provider,
      nativeBalance: nativeBalance ?? this.nativeBalance,
      hasAOSignature: hasAOSignature ?? this.hasAOSignature,
    );
  }

  @override
  List<Object?> get props =>
      [address, chainId, provider, nativeBalance, hasAOSignature];
}

/// State of a connected Solana wallet
class SolanaWalletState extends Equatable {
  /// Wallet public key (base58)
  final String address;

  /// Which provider is connected
  final SolanaWalletProvider provider;

  /// Balance in lamports
  final BigInt? balance;

  const SolanaWalletState({
    required this.address,
    required this.provider,
    this.balance,
  });

  /// Truncated address for display
  String get truncatedAddress {
    if (address.length < 10) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }

  /// Display name with provider
  String get displayWithProvider => '$truncatedAddress (${provider.displayName})';

  /// Balance in SOL (from lamports)
  double? get balanceInSol =>
      balance != null ? balance!.toDouble() / 1e9 : null;

  SolanaWalletState copyWith({
    String? address,
    SolanaWalletProvider? provider,
    BigInt? balance,
  }) {
    return SolanaWalletState(
      address: address ?? this.address,
      provider: provider ?? this.provider,
      balance: balance ?? this.balance,
    );
  }

  @override
  List<Object?> get props => [address, provider, balance];
}

/// Token balance information
class TokenBalance extends Equatable {
  /// Token type
  final CryptoToken token;

  /// Balance in smallest unit
  final BigInt rawBalance;

  /// Whether this is stale (needs refresh)
  final bool isStale;

  /// Last updated timestamp
  final DateTime? lastUpdated;

  /// Any error fetching balance
  final String? error;

  /// Whether this is a network error (blocks proceeding)
  final bool isNetworkError;

  /// Whether balance is currently loading
  final bool isLoading;

  /// USD value of the balance (if available)
  final double? usdValue;

  const TokenBalance({
    required this.token,
    required this.rawBalance,
    this.isStale = false,
    this.lastUpdated,
    this.error,
    this.isNetworkError = false,
    this.isLoading = false,
    this.usdValue,
  });

  /// Alias for rawBalance for API compatibility
  double get balance => balanceDisplay;

  /// Whether there's an error
  bool get hasError => error != null;

  /// Balance in human-readable units
  double get balanceDisplay {
    final divisor = switch (token.decimals) {
      6 => 1e6,
      9 => 1e9,
      18 => 1e18,
      _ => 1e6,
    };
    return rawBalance.toDouble() / divisor;
  }

  /// Formatted balance with symbol for display
  String get displayBalance {
    final decimals = switch (token) {
      CryptoToken.ethBase || CryptoToken.ethL1 => 6,
      CryptoToken.sol => 4,
      _ => 2,
    };
    return '${balanceDisplay.toStringAsFixed(decimals)} ${token.symbol}';
  }

  /// Alias for displayBalance
  String get formattedBalance => displayBalance;

  /// Whether the balance is sufficient for a given amount (in smallest unit)
  bool isSufficientFor(BigInt amount) => rawBalance >= amount;

  /// Whether the balance is sufficient including gas (for native tokens)
  bool isSufficientWithGas(BigInt amount, BigInt gasEstimate) {
    if (!token.isNativeToken) return isSufficientFor(amount);
    return rawBalance >= (amount + gasEstimate);
  }

  factory TokenBalance.zero(CryptoToken token) => TokenBalance(
        token: token,
        rawBalance: BigInt.zero,
      );

  factory TokenBalance.loading(CryptoToken token) => TokenBalance(
        token: token,
        rawBalance: BigInt.zero,
        isLoading: true,
      );

  factory TokenBalance.error(CryptoToken token, String error,
      {bool isNetworkError = false}) {
    return TokenBalance(
      token: token,
      rawBalance: BigInt.zero,
      error: error,
      isNetworkError: isNetworkError,
    );
  }

  TokenBalance copyWith({
    CryptoToken? token,
    BigInt? rawBalance,
    bool? isStale,
    DateTime? lastUpdated,
    String? error,
    bool? isNetworkError,
    bool? isLoading,
    double? usdValue,
  }) {
    return TokenBalance(
      token: token ?? this.token,
      rawBalance: rawBalance ?? this.rawBalance,
      isStale: isStale ?? this.isStale,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      error: error ?? this.error,
      isNetworkError: isNetworkError ?? this.isNetworkError,
      isLoading: isLoading ?? this.isLoading,
      usdValue: usdValue ?? this.usdValue,
    );
  }

  @override
  List<Object?> get props =>
      [token, rawBalance, isStale, lastUpdated, error, isNetworkError, isLoading, usdValue];
}
