import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
// ignore: depend_on_referenced_packages
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

abstract class EthereumWallet extends Wallet {
  /// Returns 12-word seed phrase derived from first half of message hash and full message hash.
  Future<(String, Uint8List)> deriveArdriveSeedphrase(
      int chainId, String password) async {
    final address = await getAddress();
    final messageText = '$chainId:$address:$password';
    final messageHash = await sha256.hash(utf8.encode(messageText));
    final messageHex = hex.encode(messageHash.bytes);

    final messageData = utf8.encode(messageHex) as Uint8List;
    final signature = await sign(messageData);

    final signatureSha256 = await sha256.hash(signature);

    // use first 16 bytes of signature to generate 12-word mnemonic
    final halfSignature = signatureSha256.bytes.sublist(0, 16);

    // entropyToMnemonic expects hex encoding
    final signatureHex = hex.encode(halfSignature);

    final bip39Mnemonnic = bip39.entropyToMnemonic(signatureHex);

    return (bip39Mnemonnic, Uint8List.fromList(signatureSha256.bytes));
  }

  // RsaPublicKey is not applicable for Ethereum
  @override
  Future<RsaPublicKey> getPublicKey() async => throw UnimplementedError();
}
