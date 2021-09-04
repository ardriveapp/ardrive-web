import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;

import '../services.dart';

final aesGcm = AesGcm.with256bits();

/// Decrypts the provided transaction details and data into JSON using the provided key.
///
/// Throws a [TransactionDecryptionException] if decryption fails.
Future<Map<String, dynamic>?> decryptEntityJson(
  TransactionCommonMixin transaction,
  Uint8List data,
  SecretKey key,
) async {
  final decryptedData = await decryptTransactionData(transaction, data, key);
  return json.decode(utf8.decode(decryptedData));
}

/// Decrypts the provided transaction details and data into a [Uint8List] using the provided key.
///
/// Throws a [TransactionDecryptionException] if decryption fails.
Future<Uint8List> decryptTransactionData(
  TransactionCommonMixin transaction,
  Uint8List data,
  SecretKey key,
) async {
  final cipher = transaction.getTag(EntityTag.cipher);

  try {
    if (cipher == Cipher.aes256) {
      final cipherIv =
          utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

      return aesGcm
          .decrypt(
            secretBoxFromDataWithMacConcatenation(data, nonce: cipherIv),
            secretKey: key,
          )
          .then((res) => Uint8List.fromList(res));
    }
  } on SecretBoxAuthenticationError catch (_) {
    throw TransactionDecryptionException();
  }

  throw ArgumentError();
}

/// Creates a transaction with the provided entity's JSON data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedEntityTransaction(
        Entity entity, SecretKey key) =>
    createEncryptedTransaction(utf8.encode(json.encode(entity)) as Uint8List, key);

/// Creates a data item with the provided entity's JSON data encrypted along with the appropriate cipher tags.
Future<DataItem> createEncryptedEntityDataItem(Entity entity, SecretKey key) =>
    createEncryptedDataItem(utf8.encode(json.encode(entity)) as Uint8List, key);

/// Creates a [Transaction] with the provided data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedTransaction(
  Uint8List data,
  SecretKey key,
) async {
  final encryptionRes = await aesGcm.encrypt(data, secretKey: key);

  return Transaction.withBlobData(
      // The encrypted data should be a concatenation of the cipher text and MAC.
      data: encryptionRes.concatenation(nonce: false))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(encryptionRes.nonce),
    );
}

/// Creates a [DataItem] with the provided data encrypted along with the appropriate cipher tags.
Future<DataItem> createEncryptedDataItem(
  Uint8List data,
  SecretKey key,
) async {
  final encryptionRes = await aesGcm.encrypt(data.toList(), secretKey: key);

  return DataItem.withBlobData(
      // The encrypted data should be a concatenation of the cipher text and MAC.
      data: encryptionRes.concatenation(nonce: false))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(encryptionRes.nonce),
    );
}

class TransactionDecryptionException implements Exception {}
