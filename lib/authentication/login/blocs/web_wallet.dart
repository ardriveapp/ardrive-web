@JS('ArweaveWallet')
library ArweaveWallet;

import 'dart:convert';
import 'dart:js_util';

import 'package:arweave/arweave.dart';
import 'package:js/js.dart';

@JS('generateJWKStringFromMnemonic')
external String _generateJWKStringFromMnemonic(String mnemonic);

Future<Wallet> generateWalletFromMnemonic(String mnemonic) async {
  var jwk = await promiseToFuture(_generateJWKStringFromMnemonic(mnemonic));
  return Wallet.fromJwk(json.decode(jwk));
}
