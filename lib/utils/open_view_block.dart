import 'package:ardrive/utils/open_url.dart';

void openViewBlockWallet(String walletAddress) {
  openUrl(url: 'https://viewblock.io/arweave/address/$walletAddress');
}

/// Opens the appropriate block explorer for the given wallet address.
/// Detects Ethereum (0x prefix), Solana (base58, 32-44 chars), or Arweave.
void openWalletExplorer(String address) {
  if (address.startsWith('0x')) {
    openUrl(url: 'https://etherscan.io/address/$address');
  } else if (!address.contains('-') &&
      !address.contains('_') &&
      address.length >= 32 &&
      address.length <= 44) {
    openUrl(url: 'https://solscan.io/account/$address');
  } else {
    openUrl(url: 'https://viewblock.io/arweave/address/$address');
  }
}
