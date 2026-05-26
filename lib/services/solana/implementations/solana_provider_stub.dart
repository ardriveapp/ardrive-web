import 'dart:typed_data';

import '../solana_provider.dart';

bool isExtensionPresent() => false;

SolanaLoginProviderDetection detectProviders() {
  return const SolanaLoginProviderDetection();
}

Future<SolanaConnection?> connect({String? provider}) =>
    throw UnimplementedError();

Future<Uint8List> signMessage(String message) => throw UnimplementedError();

Future<void> disconnect() async {}
