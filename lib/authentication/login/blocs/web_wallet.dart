@JS('ArweaveWallet')
library ArweaveWallet;

import 'dart:js_util';

import "package:js/js.dart";

@JS('generateJWKStringFromMnemonic')
external String _generateJWKStringFromMnemonic(String mnemonic);

Future<String> generateJWKStringFromMnemonic(String mnemonic) {
  return promiseToFuture(_generateJWKStringFromMnemonic(mnemonic));
}
