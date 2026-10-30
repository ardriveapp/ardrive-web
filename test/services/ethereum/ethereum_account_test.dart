import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/ethereum/ethereum_account.dart';
import 'package:ardrive/services/ethereum/provider/ethereum_provider_wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webthree/credentials.dart';

void main() {
  // A throwaway key, for vectors only.
  final key = EthPrivateKey.fromHex(
      '4c0883a69102937d6231471b5dbb6204fe5129617082792ae468d01a3f362318');
  final wallet = EthereumProviderWallet(key);

  group('ethereumAccountMessage', () {
    test('is fixed, byte for byte', () {
      expect(
        ethereumAccountMessage('0x2C7536E3605D9C16a7a3D7b1898e529396a65c23'),
        'ArDrive account\n'
        'Signing this opens your ArDrive account. Only sign it in ArDrive.\n'
        'It is free and sends no transaction.\n'
        'Account: 0x2c7536e3605d9c16a7a3d7b1898e529396a65c23\n'
        'Version: 2',
      );
    });

    test('is the same for any case of the address', () {
      expect(
        ethereumAccountMessage('0xABCDEF0000000000000000000000000000000001'),
        ethereumAccountMessage('0xabcdef0000000000000000000000000000000001'),
      );
    });

    test('differs from the sign-in message and the device unlock', () {
      expect(ethereumAccountMessage('0x01'), isNot(ethereumVerifyMessage));
      expect(ethereumAccountMessage('0x01'), contains('Version: 2'));
    });
  });

  group('deriveEthereumAccountMnemonic', () {
    test('gives the same 12 words every time for one account', () async {
      final first = await deriveEthereumAccountMnemonic(wallet);
      final second = await deriveEthereumAccountMnemonic(wallet);

      expect(first.split(' '), hasLength(12));
      expect(second, first);
    });

    test('matches the vector', () async {
      // Pinned: a change here gives every version 2 account another wallet.
      expect(
        await deriveEthereumAccountMnemonic(wallet),
        'public noise grape run swing rescue help decorate behind member '
        'client marble',
      );
    });

    test('signs the account message, not the password scheme', () async {
      final address = await wallet.getAddress();
      final signature = await wallet.sign(Uint8List.fromList(
          utf8.encode(ethereumAccountMessage(address))));

      expect(
        await deriveMnemonicFromEthereumAccountSignature(signature),
        await deriveEthereumAccountMnemonic(wallet),
      );
    });

    test('another account gets another phrase', () async {
      final other = EthereumProviderWallet(EthPrivateKey.fromHex(
          '8da4ef21b864d2cc526dbdb2a120bd2874c36c9d0a1fb7f8c63d7f7a8b41de8f'));

      expect(
        await deriveEthereumAccountMnemonic(other),
        isNot(await deriveEthereumAccountMnemonic(wallet)),
      );
    });

    test('refuses a signature that is not 65 bytes', () {
      expect(
        () => deriveMnemonicFromEthereumAccountSignature(Uint8List(64)),
        throwsArgumentError,
      );
    });
  });
}
