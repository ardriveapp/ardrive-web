import 'package:ardrive/utils/logger.dart';
import 'package:js/js.dart';
import 'package:universal_html/html.dart';
import 'package:webthree/browser.dart';

import '../ethereum_provider_wallet.dart';

bool isExtensionPresent() => window.ethereum != null;

Ethereum getProvider() {
  if (isExtensionPresent()) {
    return window.ethereum!;
  } else {
    throw Exception('Ethereum provider is not present');
  }
}

@JS()
@anonymous
class JSrawRequestParams {
  external String get chainId;

  external factory JSrawRequestParams({String chainId});
}

Future<EthereumProviderWallet?> connect() async {
  final eth = getProvider();

  try {
    final credentials = await eth.requestAccounts();

    if (!eth.isConnected()) {
      return null;
    }

    // Ensure the user is on Ethereum chain
    await eth.rawRequest(
      'wallet_switchEthereumChain',
      params: [
        JSrawRequestParams(chainId: '0x1'),
      ],
    );

    return EthereumProviderWallet(credentials[0]);
  } catch (e) {
    logger.d('Error connecting to Ethereum provider: $e');
    return null;
  }
}
