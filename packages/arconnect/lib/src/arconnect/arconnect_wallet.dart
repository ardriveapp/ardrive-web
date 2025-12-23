import 'package:arconnect/src/arconnect/arconnect.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter/foundation.dart';

class ArConnectWallet extends Wallet {
  ArConnectWallet(this.arConnectService, {super.onSign}) {
    debugPrint('ArConnectWallet instantiated');
  }

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
  Future<Uint8List> sign(Uint8List message, [String? context]) async {
    onSign?.call('ArConnect signing ${message.length} bytes', context);
    debugPrint('ArConnectWallet.sign() called with context: $context');
    return await arConnectService.getSignature(message);
  }
}
