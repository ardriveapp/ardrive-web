import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:arweave/arweave.dart';

class ArConnectWallet extends Wallet {
  ArConnectService arConnectService = ArConnectService();

  @override
  Future<String> getOwner() {
    return arConnectService.getPublicKey();
  }

  @override
  Future<String> getAddress() {
    return arConnectService.getWalletAddress();
  }

  @override
  Future<Uint8List> sign(Uint8List message) async {
    return arConnectService.getSignature(message);
  }
}
