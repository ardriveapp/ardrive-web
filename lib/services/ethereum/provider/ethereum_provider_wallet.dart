import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:webthree/credentials.dart';

import '../ethereum_wallet.dart';

class EthereumProviderWallet extends EthereumWallet {
  final CredentialsWithKnownAddress credentials;

  EthereumProviderWallet(this.credentials);

  // Ethereum Provider accepts an optional chainId parameter
  @override
  Future<Uint8List> sign(
    Uint8List message, {
    int? chainId,
  }) async {
    final signature =
        await credentials.signPersonalMessage(message, chainId: chainId);
    return signature;
  }

  @override
  SignatureConfig getSignatureConfig() {
    return SignatureConfig.ethereum;
  }

  @override
  Future<String> getAddress() {
    return Future.value(credentials.address.hex);
  }

  @override
  Future<String> getOwner() async {
    if (credentials is EthPrivateKey) {
      EthPrivateKey ethPrivateKey = credentials as EthPrivateKey;
      final pubKey = [0x04] + ethPrivateKey.encodedPublicKey;
      return base64UrlEncode(pubKey);
    }
    throw UnimplementedError();
  }

  // JWK is not applicable for Ethereum Provider
  @override
  Map<String, dynamic> toJwk() => throw UnimplementedError();
}
