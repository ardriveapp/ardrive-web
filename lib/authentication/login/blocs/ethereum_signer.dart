import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:webthree/credentials.dart';

class EthereumSigner implements Signer {
  final CredentialsWithKnownAddress credentialsWithKnownAddress;

  EthereumSigner(this.credentialsWithKnownAddress);

  @override
  SignatureConfig get signatureConfig => SignatureConfig.ethereum;

  @override
  Future<Uint8List> sign(Uint8List message) {
    return credentialsWithKnownAddress.signPersonalMessage(message);
  }
}
