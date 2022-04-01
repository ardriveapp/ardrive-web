import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:arweave/arweave.dart';

class ArConnectWallet extends Wallet {
  ArConnectService arConnectService = ArConnectService();

  @override
  Future<String> getOwner() async {
    return await arConnectService.getPublicKey();
  }

  @override
  Future<String> getAddress() async {
    return await arConnectService.getWalletAddress();
  }

  @override
  Future<Uint8List> signMessage(Uint8List message) async {
    return await arConnectService.getSignature(message);
  }

  @override
  Future<TransactionBase> sign(TransactionBase transaction) async {
    final signedTransaction = await arConnectService.signTransaction(
      json.encode(transaction.toUnsignedJson()),
    );
    
    if (transaction is DataItem) {
      return DataItem.fromJson(json.decode(signedTransaction));
    } else {
      return Transaction.fromJson(json.decode(signedTransaction));
    }
  }
}
