import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';

// TODO: we may wnat to have this implemented on arweave-dart
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
