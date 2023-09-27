import 'dart:html';

import 'package:webthree/browser.dart';

import '../ethereum_provider_wallet.dart';

bool isExtensionPresent() => window.ethereum != null;

Ethereum _getProvider() {
  if (isExtensionPresent()) {
    return window.ethereum!;
  } else {
    throw Exception('Ethereum provider is not present');
  }
}

Future<EthereumProviderWallet?> connect() async {
  final eth = _getProvider();

  final credentials = await eth.requestAccount();
  if (!eth.isConnected()) {
    return null;
  }

  final address = credentials.address;

  return EthereumProviderWallet(credentials, address.hex);
}
