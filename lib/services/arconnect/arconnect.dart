@JS()
library arconnect;

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:moor/moor.dart';

@JS('isExtensionPresent')
external bool isExtensionPresent();

@JS('connect')
external dynamic _connect();

@JS('getWalletAddress')
external String _getWalletAddress();

@JS('getSignature')
external Uint8List _getSignature(Object message);

Future<void> connect() {
  return promiseToFuture(_connect());
}

Future<String> getWalletAddress() {
  return promiseToFuture(_getWalletAddress());
}

Future<Uint8List> getSignature(Uint8List message) {
  print(message);
  final promise = _getSignature(message);
  return promiseToFuture(promise);
}
