import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:arweave/arweave.dart';

class ArConnectWallet extends Wallet {
  ArConnectWallet(this.arConnectService);

  final ArConnectService arConnectService;

  @override
  Future<String> getOwner() async {
    return await arConnectService.getPublicKey();
  }

  @override
  Future<String> getAddress() async {
    return await arConnectService.getWalletAddress();
  }

  @override
  Future<Uint8List> sign(Uint8List message) async {
    return await arConnectService.getSignature(message);
  }

  @override
  Future<Uint8List> signDataItem(DataItem dataItem) async {
    return await arConnectService.signDataItem(dataItem);
  }
}
