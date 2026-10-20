import 'package:ardrive/utils/open_url.dart';

void openViewBlockWallet(String walletAddress) {
  openUrl(url: 'https://viewblock.io/arweave/address/$walletAddress');
}

/// Returns the block explorer URL for [address].
///
/// An Arweave address and a Solana address can look alike (43 characters, a
/// chance of no `-` or `_`), so the caller says which one it holds with
/// [isArweave]. For a non-Arweave address, `0x` means Ethereum, else Solana.
String walletExplorerUrl(String address, {required bool isArweave}) {
  if (isArweave) {
    return 'https://viewblock.io/arweave/address/$address';
  }
  if (address.startsWith('0x')) {
    return 'https://etherscan.io/address/$address';
  }
  return 'https://solscan.io/account/$address';
}

/// Opens the block explorer for the given wallet address.
void openWalletExplorer(String address, {required bool isArweave}) {
  openUrl(url: walletExplorerUrl(address, isArweave: isArweave));
}
