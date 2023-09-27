import 'dart:async';
import 'dart:typed_data';

import 'package:webthree/credentials.dart';

import '../ethereum_wallet.dart';

class EthereumProviderWallet extends EthereumWallet {
  final CredentialsWithKnownAddress credentials;
  final String address;

  EthereumProviderWallet(this.credentials, this.address);

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
  Future<String> getAddress() {
    return Future.value(address);
  }

  @override
  Future<String> getOwner() {
    return Future.value(address);
  }

  // JWK is not applicable for Ethereum Provider
  @override
  Map<String, dynamic> toJwk() => throw UnimplementedError();
}
