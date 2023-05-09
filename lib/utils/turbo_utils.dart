import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

String publicKeyToHeader(RsaPublicKey publicKey) {
  return base64UrlEncode(json.encode(
    {
      'kty': 'RSA',
      'n': base64UrlEncode(publicKey.n),
      'e': base64UrlEncode(publicKey.e),
    },
  ).codeUnits);
}

Future<String> signNonceAndData({
  required Wallet wallet,
  required String nonce,
  String? data,
}) async {
  final signature = await wallet.sign(
    Uint8List.fromList(
      (data != null ? '$data$nonce' : nonce).toString().codeUnits,
    ),
  );
  return base64UrlEncode(signature);
}
