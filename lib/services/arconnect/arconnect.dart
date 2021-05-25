@JS()
library arconnect;

import 'package:js/js.dart';
import 'package:js/js_util.dart';
import 'package:moor/moor.dart';

@JS('isExtensionPresent')
external bool isExtensionPresent();

@JS('connect')
external dynamic _connect();

@JS('connect')
external dynamic _disconnect();

@JS('getWalletAddress')
external String _getWalletAddress();

@JS('getPublicKey')
external String _getPublicKey();

@JS('getSignature')
external Uint8List _getSignature(Uint8List message);

Future<void> connect() {
  return promiseToFuture(_connect());
}

Future<void> disconnect() {
  return promiseToFuture(_disconnect());
}

Future<String> getWalletAddress() {
  return promiseToFuture(_getWalletAddress());
}

Future<String> getPublicKey() async {
  return await promiseToFuture(_getPublicKey());
}

Future<Uint8List> getSignature(Uint8List message) async {
  final result = promiseToFuture<Uint8List>(_getSignature(message));
  return result;
}
