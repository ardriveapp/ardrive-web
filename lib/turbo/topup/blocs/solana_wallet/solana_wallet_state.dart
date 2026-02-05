part of 'solana_wallet_cubit.dart';

/// Base class for Solana wallet states
@immutable
abstract class SolanaWalletCubitState extends Equatable {
  const SolanaWalletCubitState();

  @override
  List<Object?> get props => [];
}

/// Wallet is disconnected
class SolanaWalletDisconnected extends SolanaWalletCubitState {
  const SolanaWalletDisconnected();
}

/// Wallet is connecting
class SolanaWalletConnecting extends SolanaWalletCubitState {
  final SolanaWalletProvider? provider;

  const SolanaWalletConnecting({this.provider});

  @override
  List<Object?> get props => [provider];
}

/// Wallet is connected
class SolanaWalletConnectedState extends SolanaWalletCubitState {
  final String address;
  final SolanaWalletProvider provider;
  final TokenBalance? balance;

  const SolanaWalletConnectedState({
    required this.address,
    required this.provider,
    this.balance,
  });

  /// Truncated address for display
  String get truncatedAddress {
    if (address.length < 10) return address;
    return '${address.substring(0, 4)}...${address.substring(address.length - 4)}';
  }

  SolanaWalletConnectedState copyWith({
    String? address,
    SolanaWalletProvider? provider,
    TokenBalance? balance,
  }) {
    return SolanaWalletConnectedState(
      address: address ?? this.address,
      provider: provider ?? this.provider,
      balance: balance ?? this.balance,
    );
  }

  @override
  List<Object?> get props => [address, provider, balance];
}

/// Wallet error state
class SolanaWalletErrorState extends SolanaWalletCubitState {
  final String message;
  final bool isUserRejected;
  final bool isNotInstalled;

  const SolanaWalletErrorState({
    required this.message,
    this.isUserRejected = false,
    this.isNotInstalled = false,
  });

  @override
  List<Object?> get props => [message, isUserRejected, isNotInstalled];
}
