/// Service for interacting with Ethereum wallets via browser extensions.
///
/// Supports MetaMask, Coinbase Wallet, Rainbow, and other injected providers.
/// Uses the CryptoWalletBridge JavaScript API for wallet communication.
library ethereum_wallet_service;

export 'implementations/ethereum_wallet_service_stub.dart'
    if (dart.library.html) 'implementations/ethereum_wallet_service_web.dart';
