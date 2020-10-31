import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/entities.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;

import '../services.dart';

/// Decrypts the provided transaction details and data into JSON using the provided key.
///
/// Throws a [TransactionDecryptionException] if decryption fails.
Future<Map<String, dynamic>> decryptEntityJson(
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
          utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv));

      return aesGcm.decrypt(
        data,
        secretKey: key,
        nonce: Nonce(cipherIv),
      );
    }
  } catch (err) {
    if (err is MacValidationException) {
      throw TransactionDecryptionException();
    }

    rethrow;
  }

  throw ArgumentError();
}

/// Creates a transaction with the provided entity's JSON data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedEntityTransaction(
        Entity entity, SecretKey key) =>
    createEncryptedTransaction(utf8.encode(json.encode(entity)), key);

/// Creates a transaction with the provided data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedTransaction(
  Uint8List data,
  SecretKey key,
) async {
  final iv = Nonce.randomBytes(96 ~/ 8);
  final encryptedData = await aesGcm.encrypt(data, secretKey: key, nonce: iv);

  return Transaction.withBlobData(data: encryptedData)
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(iv.bytes),
    );
}

class TransactionDecryptionException implements Exception {}
