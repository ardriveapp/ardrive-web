// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:js_util';

import 'package:ardrive/utils/logger.dart';
import 'package:js/js.dart';

@JS('globalThis')
external Object get _globalThis;

bool metaMaskDetected() {
  try {
    final bridge = getProperty(_globalThis, 'CryptoWalletBridge');
    if (bridge == null) return false;
    final found = callMethod(bridge, 'detectEthereumProviders', []);
    return getProperty(found, 'metamask') == true &&
        getProperty(found, 'coinbaseWallet') != true &&
        getProperty(found, 'brave') != true;
  } catch (e) {
    logger.w('Could not detect the Ethereum wallet: $e');
    return false;
  }
}
