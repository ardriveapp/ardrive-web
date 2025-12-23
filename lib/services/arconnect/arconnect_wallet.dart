import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';

class ArConnectWallet extends Wallet {
  ArConnectWallet(this.arConnectService, {super.onSign}) {
    logger.d('ArConnectWallet instantiated');
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
    logger.d('ArConnectWallet.sign() called with context: $context');
    return await arConnectService.getSignature(message);
  }

  @override
  Future<Uint8List> signDataItem(DataItem dataItem, [String? context]) async {
    onSign?.call(
        'ArConnect signing DataItem ${dataItem.data.length} bytes', context);
    logger.d('ArConnectWallet.signDataItem() called with context: $context');
    return await arConnectService.signDataItem(dataItem);
  }
}
