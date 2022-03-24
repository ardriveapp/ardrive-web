import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';

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
  Future<Uint8List> sign(TransactionBase transaction) async {
    final signature = await arConnectService.signTransaction(
      json.encode(transaction.toUnsignedJson()),
    );
    return decodeBase64ToBytes(signature);
  }
}
