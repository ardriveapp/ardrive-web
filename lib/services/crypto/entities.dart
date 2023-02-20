import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/services/crypto/stream_aes.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;

final aesGcm = AesGcm.with256bits();
final aesCtr = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);

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
    switch (cipher) {
      case Cipher.aes256gcm:
        final cipherIv =
            utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

        return aesGcm
            .decrypt(
              secretBoxFromDataWithMacConcatenation(data, nonce: cipherIv),
              secretKey: key,
            )
            .then((res) => Uint8List.fromList(res));
      
      case Cipher.aes256ctr:
        final cipherIv =
            utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

        return aesCtr
            .decrypt(
              SecretBox(data, nonce: cipherIv, mac: Mac.empty),
              secretKey: key,
            )
            .then((res) => Uint8List.fromList(res));
    }
  } on SecretBoxAuthenticationError catch (_) {
    throw TransactionDecryptionException();
  }

  throw ArgumentError();
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

  switch (cipher) {
    case Cipher.aes256gcm:
      final cipherIv =
          utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

      final aesGcm = await AesGcmStream.fromKeyData(keyData);
      final res = await aesGcm.decryptStream(
        cipherIv,
        dataStream,
        int.parse(transaction.data.size)
      );
      return res.stream;
    
    case Cipher.aes256ctr:
      final cipherIv =
          utils.decodeBase64ToBytes(transaction.getTag(EntityTag.cipherIv)!);

      final aesCtr = await AesCtrStream.fromKeyData(keyData);
      final res = await aesCtr.decryptStream(
        cipherIv,
        dataStream,
        int.parse(transaction.data.size)
      );
      return res.stream;
  }

  throw ArgumentError();
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
  SecretKey key,
) async {
  final encryptionRes = await aesGcm.encrypt(data, secretKey: key);

  return Transaction.withBlobData(
      // The encrypted data should be a concatenation of the cipher text and MAC.
      data: encryptionRes.concatenation(nonce: false))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256gcm)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(encryptionRes.nonce),
    );
}

/// Creates a [TransactionStream] with the provided data encrypted along with the appropriate cipher tags.
Future<TransactionStream> createEncryptedTransactionStream(
  DataStreamGenerator plaintextDataStreamGenerator,
  int streamLength,
  SecretKey key,
) async {
  final keyData = Uint8List.fromList(await key.extractBytes());
  final aesCtr = await AesCtrStream.fromKeyData(keyData);
  
  final encryptStreamResult = await aesCtr.encryptStreamGenerator(plaintextDataStreamGenerator, streamLength);
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
  SecretKey key,
) async {
  final encryptionRes = await aesGcm.encrypt(data.toList(), secretKey: key);

  return DataItem.withBlobData(
      // The encrypted data should be a concatenation of the cipher text and MAC.
      data: encryptionRes.concatenation(nonce: false))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256gcm)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(encryptionRes.nonce),
    );
}

class TransactionDecryptionException implements Exception {}
