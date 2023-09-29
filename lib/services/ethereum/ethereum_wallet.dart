import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:arweave/arweave.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';

abstract class EthereumWallet extends Wallet {
  Future<String> deriveArdriveSeedphrase() async {
    // Magic string for deriving the Arweave Key
    const messageText = 'Arweave Key Seed';

    final messageData = utf8.encode(messageText) as Uint8List;
    final signature = await sign(messageData);

    final signatureSha256 = await sha256.hash(signature);
    // entropyToMnemonic expects hex encoding
    final signatureHex = hex.encode(signatureSha256.bytes);

    final bip39Mnemonnic = bip39.entropyToMnemonic(signatureHex);

    return bip39Mnemonnic;
  }

  // RsaPublicKey is not applicable for Ethereum
  @override
  Future<RsaPublicKey> getPublicKey() async => throw UnimplementedError();
}
