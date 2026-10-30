import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
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
      final signature = await wallet.sign(
          Uint8List.fromList(utf8.encode(ethereumAccountMessage(address))));

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

  group('finding the account record', () {
    const marker = AccountRecordTx(id: 'marker', tags: {
      'App-Name': 'ArDrive',
      'ArDrive-Account-Version': '2',
      'ArDrive-Account-Address': 'arweave-address',
    });
    const v1 = AccountRecordTx(id: 'v1');

    test('a marker is version 2, with its address', () {
      final found = classifyAccountRecords([marker]);
      expect(found, isA<EthereumV2Marker>());
      expect((found as EthereumV2Marker).accountAddress, 'arweave-address');
    });

    test('an untagged record is version 1', () {
      expect(classifyAccountRecords([v1]), isA<EthereumV1Record>());
      expect(classifyAccountRecords([]), isNull);
    });

    test('a marker wins over a version 1 record', () {
      expect(classifyAccountRecords([v1, marker]), isA<EthereumV2Marker>());
    });

    test(
        '"no record" only when the configured endpoint and the turbo-gateway '
        'index both answer with none', () async {
      final asked = <String>[];
      Future<List<AccountRecordTx>> Function() endpoint(
              String name, List<AccountRecordTx> answer) =>
          () async {
            asked.add(name);
            return answer;
          };

      expect(
        await findAccountRecordAcross([
          endpoint('configured', []),
          () => firstReachable([
                endpoint('turbo-gateway.com', []),
                endpoint('ardrive.net', []),
              ]),
        ]),
        isNull,
      );
      expect(asked, ['configured', 'turbo-gateway.com']);
    });

    test('a record only the turbo-gateway index has is found', () async {
      expect(
        await findAccountRecordAcross([
          () async => [],
          () async => [v1],
        ]),
        isA<EthereumV1Record>(),
      );
    });

    test('the first record found is the answer; later endpoints are not asked',
        () async {
      var later = 0;
      final found = await findAccountRecordAcross([
        () async => [marker],
        () async {
          later++;
          return [];
        },
      ]);
      expect(found, isA<EthereumV2Marker>());
      expect(later, 0);
    });

    test(
        'the configured endpoint failing (a 429, say) is a failure, never '
        '"no record"', () async {
      await expectLater(
        findAccountRecordAcross([
          () async => throw Exception('429 Too Many Requests'),
          () async => [],
        ]),
        throwsException,
      );
    });

    test('turbo-gateway.com unreachable: ardrive.net answers for the index',
        () async {
      expect(
        await findAccountRecordAcross([
          () async => [],
          () => firstReachable([
                () async => throw Exception('blocked'),
                () async => [v1],
              ]),
        ]),
        isA<EthereumV1Record>(),
      );
    });

    test(
        'the index unreachable on both domains is a failure, never '
        '"no record"', () async {
      await expectLater(
        findAccountRecordAcross([
          () async => [],
          () => firstReachable<List<AccountRecordTx>>([
                () async => throw Exception('blocked'),
                () async => throw Exception('503'),
              ]),
        ]),
        throwsA(isA<AccountLookupUnavailable>()),
      );
    });

    test('the turbo-gateway index, by its domains: no Goldsky, no arweave.net',
        () {
      expect(ArweaveService.turboGatewayIndexDomains, [
        'https://turbo-gateway.com/graphql',
        'https://ardrive.net/graphql',
      ]);
    });

    test('the marker\'s tags', () {
      expect(ethereumAccountMarkerTags('arweave-address'), {
        'App-Name': 'ArDrive',
        'ArDrive-Account-Version': '2',
        'ArDrive-Account-Address': 'arweave-address',
      });
    });
  });
}
