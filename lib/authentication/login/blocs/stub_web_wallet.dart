import 'package:arweave/arweave.dart';

Future<Wallet> generateWalletFromMnemonic(String mnemonic) async {
  return Wallet.createWalletFromMnemonic(mnemonic);
}
