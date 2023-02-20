import 'dart:typed_data';

import 'package:ardrive/services/arweave/graphql/graphql.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart' show SecretKey;

abstract class Decrypt {
  factory Decrypt() => _Decrypt();

  Future<Uint8List> decryptTransactionData(
    TransactionCommonMixin transaction,
    Uint8List data,
    SecretKey key,
  );

  Future<Stream<Uint8List>> decryptTransactionDataStream(
    TransactionCommonMixin transaction,
    Stream<Uint8List> dataStream,
    Uint8List keyData,
  );
}

class _Decrypt implements Decrypt {
  @override
  Future<Uint8List> decryptTransactionData(
    TransactionCommonMixin transaction,
    Uint8List data,
    SecretKey key,
  ) async {
    final decryptedData = await crypto.decryptTransactionData(
      transaction,
      data,
      key,
    );

    return decryptedData;
  }

  @override
  Future<Stream<Uint8List>> decryptTransactionDataStream(
    TransactionCommonMixin transaction,
    Stream<Uint8List> dataStream,
    Uint8List keyData,
  ) {
    final decryptedData = crypto.decryptTransactionDataStream(
      transaction,
      dataStream,
      keyData,
    );

    return decryptedData;
  }
}
