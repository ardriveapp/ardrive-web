import 'package:ardrive/utils/open_view_block.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('walletExplorerUrl', () {
    test('opens ViewBlock for an Arweave address with no - or _', () {
      // 43 characters, letters and digits only, so it also looks like Solana.
      const address = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJK123456';
      expect(address.length, 43);

      expect(
        walletExplorerUrl(address, isArweave: true),
        'https://viewblock.io/arweave/address/$address',
      );
    });

    test('opens ViewBlock for an Arweave address with - and _', () {
      const address = 'abcdefghijklmnopqrstuvwxyz-_ABCDEFGHIJK1234';

      expect(
        walletExplorerUrl(address, isArweave: true),
        'https://viewblock.io/arweave/address/$address',
      );
    });

    test('opens Etherscan for an Ethereum address', () {
      const address = '0x71C7656EC7ab88b098defB751B7401B5f6d8976F';

      expect(
        walletExplorerUrl(address, isArweave: false),
        'https://etherscan.io/address/$address',
      );
    });

    test('opens Solscan for a Solana address', () {
      const address = '9WzDXwBbmkg8ZTbNMqUxvQRAyrZzDsGYdLVL9zYtAWWM';

      expect(
        walletExplorerUrl(address, isArweave: false),
        'https://solscan.io/account/$address',
      );
    });
  });
}
