import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;

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
  final impl = cipherBufferImpl(cipher);

  final cipherIv =
      utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

  try {
    return impl
      .decrypt(
        SecretBox(data, nonce: cipherIv, mac: Mac.empty),
        secretKey: key,
      )
      .then((res) => Uint8List.fromList(res));
  } on SecretBoxAuthenticationError catch (_) {
    throw TransactionDecryptionException();
  }
}

/// Decrypts the provided transaction details and data into a [Uint8List] using the provided key.
///
/// Throws a [TransactionDecryptionException] if decryption fails.
Future<Stream<Uint8List>> decryptTransactionDataStream(
  TransactionCommonMixin transaction,
  Stream<Uint8List> dataStream,
  Uint8List keyData,
) async {
  final cipher = transaction.getTag(EntityTag.cipher);
  final impl = await cipherStreamDecryptImpl(cipher, keyData: keyData);

  final cipherIv =
      utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

  final res = await impl.decryptStream(
    cipherIv,
    dataStream,
    int.parse(transaction.data.size)
  );
  return res.stream;
}

/// Creates a transaction with the provided entity's JSON data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedEntityTransaction(
        Entity entity, SecretKey key) =>
    createEncryptedTransaction(
        utf8.encode(json.encode(entity)) as Uint8List, key);

/// Creates a data item with the provided entity's JSON data encrypted along with the appropriate cipher tags.
Future<DataItem> createEncryptedEntityDataItem(Entity entity, SecretKey key) =>
    createEncryptedDataItem(utf8.encode(json.encode(entity)) as Uint8List, key);

/// Creates a [Transaction] with the provided data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedTransaction(
  Uint8List data,
  SecretKey key, {
  String cipher = Cipher.aes256gcm,
}) async {
  final impl = cipherBufferImpl(cipher);

  final encryptionRes = await impl.encrypt(data, secretKey: key);

  return Transaction.withBlobData(
      // The encrypted data should be a concatenation of the cipher text and MAC.
      data: encryptionRes.concatenation(nonce: false))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, cipher)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(encryptionRes.nonce),
    );
}

/// Creates a [TransactionStream] with the provided data encrypted along with the appropriate cipher tags.
/// Does not support AES256-GCM.
Future<TransactionStream> createEncryptedTransactionStream(
  DataStreamGenerator plaintextDataStreamGenerator,
  int streamLength,
  SecretKey key, {
  String cipher = Cipher.aes256ctr,
}) async {
  final keyData = Uint8List.fromList(await key.extractBytes());
  final impl = await cipherStreamEncryptImpl(cipher, keyData: keyData);
  
  final encryptStreamResult = await impl.encryptStreamGenerator(plaintextDataStreamGenerator, streamLength);
  final cipherIv = encryptStreamResult.nonce;
  final ciphertextDataStreamGenerator = encryptStreamResult.streamGenerator;

  return TransactionStream.withBlobData(
      dataStreamGenerator: ciphertextDataStreamGenerator,
      dataSize: streamLength,)
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256ctr)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(cipherIv),
    );
}

/// Creates a [DataItem] with the provided data encrypted along with the appropriate cipher tags.
Future<DataItem> createEncryptedDataItem(
  Uint8List data,
  SecretKey key, {
  String cipher = Cipher.aes256gcm,
}) async {
  final impl = cipherBufferImpl(cipher);

  final encryptionRes = await impl.encrypt(data.toList(), secretKey: key);

  return DataItem.withBlobData(
      // The encrypted data should be a concatenation of the cipher text and MAC.
      data: encryptionRes.concatenation(nonce: false))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, cipher)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(encryptionRes.nonce),
    );
}

class TransactionDecryptionException implements Exception {}
