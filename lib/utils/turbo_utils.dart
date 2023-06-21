import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

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
