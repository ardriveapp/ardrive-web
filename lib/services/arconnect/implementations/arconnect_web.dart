@JS()
library arconnect;

import 'package:arweave/arweave.dart';
import 'package:drift/drift.dart';
import 'package:js/js.dart';
import 'package:js/js_util.dart';

@JS('isExtensionPresent')
external bool isExtensionPresent();

@JS('connect')
external dynamic _connect();

@JS('checkPermissions')
external bool _checkPermissions();

@JS('disconnect')
external dynamic _disconnect();

@JS('listenForWalletSwitch')
external void _listenForWalletSwitch();

@JS('getWalletAddress')
external String _getWalletAddress();

@JS('getPublicKey')
external String _getPublicKey();

@JS('getSignature')
external Uint8List _getSignature(Uint8List message);

@JS('signDataItem')
external Uint8List _signDataItem(
    Uint8List data, List<Tag> tags, String owner, String target, String anchor);

@JS('getWalletVersion')
external String _getWalletVersion();

Future<void> connect() {
  return promiseToFuture(_connect());
}

Future<bool> checkPermissions() {
  return promiseToFuture(_checkPermissions());
}

Future<void> disconnect() {
  return promiseToFuture(_disconnect());
}

void listenForWalletSwitch() {
  _listenForWalletSwitch();
}

Future<String> getWalletAddress() {
  return promiseToFuture(_getWalletAddress());
}

Future<String> getPublicKey() async {
  return await promiseToFuture(_getPublicKey());
}

Future<Uint8List> getSignature(Uint8List message) async {
  return await promiseToFuture<Uint8List>(_getSignature(message));
}

Future<Uint8List> signDataItem(DataItem dataItem) async {
  return await promiseToFuture<Uint8List>(_signDataItem(dataItem.data,
      dataItem.tags, dataItem.owner, dataItem.target, dataItem.nonce));
}

Future<String?> getWalletVersion() async {
  return await promiseToFuture<String?>(_getWalletVersion());
}
