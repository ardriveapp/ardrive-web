import 'dart:typed_data';

import 'implementations/solana_provider_web.dart'
    if (dart.library.io) 'implementations/solana_provider_stub.dart'
    as implementation;

class SolanaProviderService {
  bool isExtensionPresent() {
    return implementation.isExtensionPresent();
  }

  /// Connect to a Solana wallet.
  /// [provider] can be 'phantom', 'solflare', or null for auto-detect.
  Future<SolanaConnection?> connect({String? provider}) {
    return implementation.connect(provider: provider);
  }

  /// Signs a message with the connected Solana wallet.
  /// Returns a 64-byte Ed25519 signature.
  Future<Uint8List> signMessage(String message) {
    return implementation.signMessage(message);
  }

  Future<void> disconnect() {
    return implementation.disconnect();
  }

  /// Returns which Solana wallet providers are available.
  SolanaLoginProviderDetection detectProviders() {
    return implementation.detectProviders();
  }
}

class SolanaConnection {
  final String address;
  final String providerType; // 'phantom' or 'solflare'

  const SolanaConnection({
    required this.address,
    required this.providerType,
  });
}

class SolanaLoginProviderDetection {
  final bool hasAnyProvider;
  final bool hasPhantom;
  final bool hasSolflare;

  const SolanaLoginProviderDetection({
    this.hasAnyProvider = false,
    this.hasPhantom = false,
    this.hasSolflare = false,
  });
}
