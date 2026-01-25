/// Service for cryptocurrency payment operations.
///
/// Handles:
/// - Getting quotes for crypto top-ups
/// - Executing payments via the Turbo SDK
/// - Balance fetching for all supported tokens
/// - Gas estimation for EVM and Solana transactions
/// - Transaction retry/recovery
library crypto_payment_service;

export 'implementations/crypto_payment_service_stub.dart'
    if (dart.library.html) 'implementations/crypto_payment_service_web.dart';
