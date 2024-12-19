import 'package:ardrive/utils/open_url.dart';

void openViewBlockWallet(String walletAddress) {
  openUrl(url: 'https://viewblock.io/arweave/address/$walletAddress');
}
