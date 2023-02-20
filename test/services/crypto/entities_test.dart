// Test fails to compile when testing on chrome
@TestOn('vm')

import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/crypto/entities.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'stream_aes_test_helpers.dart';

const _aes256KeyLengthBytes = 32;

final _testKey = sequentialBytes(_aes256KeyLengthBytes);

const _testDataLength = 123 * 1024 + 123;
final _testData = sequentialBytes(_testDataLength);
Stream<Uint8List> _testDataStreamGen() => 
  bufferToStream(_testData, chunkSize: 50 * 1024);

main() {
  late final ArweaveService arweaveService;
  late final Wallet testWallet;

  setUpAll(() async {
    arweaveService = ArweaveService(Arweave());
    testWallet = await Wallet.generate();
  });

  group('createEncryptedTransactionStream function', () {
    test('preparation completes', () async {
      final transaction = await createEncryptedTransactionStream(
        _testDataStreamGen,
        _testData.length,
        SecretKey(_testKey),
      );
      final dataTxFuture = arweaveService.client.transactions.prepare(
        transaction,
        testWallet,
      );
      expect(dataTxFuture, completes);
    });
  });
}
