/// Service for interacting with Solana wallets (Phantom, Solflare).
///
/// Uses the CryptoWalletBridge JavaScript API for wallet communication.
library solana_wallet_service;

export 'implementations/solana_wallet_service_stub.dart'
    if (dart.library.html) 'implementations/solana_wallet_service_web.dart';
