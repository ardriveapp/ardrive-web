import 'dart:typed_data';

import 'package:arweave/arweave.dart';

bool isExtensionPresent() => false;

Future<void> connect() {
  throw UnimplementedError();
}

Future<bool> checkPermissions() {
  throw UnimplementedError();
}

Future<void> disconnect() {
  throw UnimplementedError();
}

void listenForWalletSwitch() {
  throw UnimplementedError();
}

Future<String> getWalletAddress() {
  throw UnimplementedError();
}

Future<String> getPublicKey() async {
  throw UnimplementedError();
}

Future<Uint8List> getSignature(Uint8List message) async {
  throw UnimplementedError();
}

Future<Uint8List> signDataItem(DataItem dataItem) async {
  throw UnimplementedError();
}
