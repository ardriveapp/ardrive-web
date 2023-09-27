import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';

abstract class EthereumWallet extends Wallet {
  // RsaPublicKey is not applicable for Ethereum
  @override
  Future<RsaPublicKey> getPublicKey() async => throw UnimplementedError();
}
