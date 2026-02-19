part of 'ethereum_wallet_cubit.dart';

/// Base class for Ethereum wallet states
@immutable
abstract class EthereumWalletCubitState extends Equatable {
  const EthereumWalletCubitState();

  @override
  List<Object?> get props => [];
}

/// Wallet is disconnected
class EthereumWalletDisconnected extends EthereumWalletCubitState {
  const EthereumWalletDisconnected();
}

/// Wallet is connecting
class EthereumWalletConnecting extends EthereumWalletCubitState {
  final EthereumWalletProvider? provider;

  const EthereumWalletConnecting({this.provider});

  @override
  List<Object?> get props => [provider];
}

/// Wallet is connected
class EthereumWalletConnectedState extends EthereumWalletCubitState {
  final String address;
  final int chainId;
  final EthereumWalletProvider provider;
  final TokenBalance? balance;

  const EthereumWalletConnectedState({
    required this.address,
    required this.chainId,
    required this.provider,
    this.balance,
  });

  /// Truncated address for display (e.g., "0x1234...5678")
  String get truncatedAddress {
    if (address.length < 10) return address;
    return '${address.substring(0, 6)}...${address.substring(address.length - 4)}';
  }

  EthereumWalletConnectedState copyWith({
    String? address,
    int? chainId,
    EthereumWalletProvider? provider,
    TokenBalance? balance,
  }) {
    return EthereumWalletConnectedState(
      address: address ?? this.address,
      chainId: chainId ?? this.chainId,
      provider: provider ?? this.provider,
      balance: balance ?? this.balance,
    );
  }

  @override
  List<Object?> get props => [address, chainId, provider, balance];
}

/// Wallet is switching networks
class EthereumWalletSwitchingNetwork extends EthereumWalletCubitState {
  final String address;
  final int currentChainId;
  final int targetChainId;
  final EthereumWalletProvider provider;

  const EthereumWalletSwitchingNetwork({
    required this.address,
    required this.currentChainId,
    required this.targetChainId,
    required this.provider,
  });

  @override
  List<Object?> get props => [address, currentChainId, targetChainId, provider];
}

/// Wallet error state
class EthereumWalletErrorState extends EthereumWalletCubitState {
  final String message;
  final bool isUserRejected;
  final bool isNotInstalled;

  const EthereumWalletErrorState({
    required this.message,
    this.isUserRejected = false,
    this.isNotInstalled = false,
  });

  @override
  List<Object?> get props => [message, isUserRejected, isNotInstalled];
}
