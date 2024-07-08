import 'package:webthree/browser.dart';

import '../ethereum_wallet.dart';
import '../provider/implementations/ethereum_provider_web.dart'
    if (dart.library.io) 'implementations/ethereum_provider_stub.dart'
    as implementation;

class EthereumProviderService {
  Ethereum getProvider() {
    return implementation.getProvider();
  }

  bool isExtensionPresent() {
    return implementation.isExtensionPresent();
  }

  Future<EthereumWallet?> connect() async {
    return await implementation.connect();
  }
}
