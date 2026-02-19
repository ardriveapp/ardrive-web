import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/utils/logger.dart';
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
  Future<Uint8List> sign(Uint8List message, [String? context]) async {
    logger.d('ArConnectWallet.sign() called with ${message.length} bytes'
        '${context != null ? ' (context: $context)' : ''}');
    try {
      final result = await arConnectService.getSignature(message);
      logger.d('ArConnectWallet.sign() successful, got ${result.length} bytes');
      return result;
    } catch (e, stackTrace) {
      logger.e('ArConnectWallet.sign() failed', e, stackTrace);
      rethrow;
    }
  }

  /// Signs a [DataItem] via ArConnect. Not part of the arweave [Wallet] interface.
  Future<Uint8List> signDataItem(DataItem dataItem) async {
    logger.d('ArConnectWallet.signDataItem() called with ${dataItem.data.length} bytes');
    try {
      final result = await arConnectService.signDataItem(dataItem);
      logger.d('ArConnectWallet.signDataItem() successful, got ${result.length} bytes');
      return result;
    } catch (e, stackTrace) {
      logger.e('ArConnectWallet.signDataItem() failed', e, stackTrace);
      rethrow;
    }
  }
}
