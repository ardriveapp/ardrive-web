@JS('ArweaveWallet')
// ignore: library_names
library ArweaveWallet;

import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util';

import 'package:arweave/arweave.dart';
import 'package:js/js.dart';

@JS('generateJWKStringFromMnemonic')
external String _generateJWKStringFromMnemonic(String mnemonic);

@JS('globalThis')
external Object get _globalThis;

Future<Wallet> generateWalletFromMnemonic(String mnemonic) async {
  // Lazy-load arweave-wallet.js if not yet loaded
  final lazyLoader = getProperty(_globalThis, 'LazyLoader');
  if (lazyLoader != null) {
    try {
      await promiseToFuture(callMethod(lazyLoader, 'loadArweaveWallet', []));
    } catch (e) {
      throw Exception('Failed to load arweave-wallet.js: $e');
    }
  }

  try {
    var jwk = await promiseToFuture(_generateJWKStringFromMnemonic(mnemonic));
    return Wallet.fromJwk(json.decode(jwk));
  } catch (e) {
    throw Exception('Failed to generate wallet from mnemonic: $e');
  }
}
