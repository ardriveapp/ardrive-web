import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:drive/repositories/entities/entity.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../../arweave/arweave.dart';
import '../entities.dart';

const keyByteLength = 256 ~/ 8;
final _uuid = Uuid();

Future<KeyParameter> deriveFileKey(KeyParameter driveKey, String fileId) async {
  final fileIdBytes = _uuid.parse(fileId);

  final fileKdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(driveKey.key, keyByteLength));

  final fileKeyOutput = Uint8List(keyByteLength);
  fileKdf.deriveKey(fileIdBytes, 0, fileKeyOutput, 0);

  return KeyParameter(fileKeyOutput);
}

Future<Map<String, dynamic>> decryptDriveEntityJson(
        TransactionCommonMixin transaction,
        Uint8List data,
        KeyParameter driveKey) =>
    _decryptEntityJson(transaction, data, driveKey);

Future<Map<String, dynamic>> decryptFolderEntityJson(
        TransactionCommonMixin transaction,
        Uint8List data,
        KeyParameter driveKey) =>
    _decryptEntityJson(transaction, data, driveKey);

Future<Map<String, dynamic>> decryptFileEntityJson(
        TransactionCommonMixin transaction,
        Uint8List data,
        KeyParameter driveKey) async =>
    _decryptEntityJson(
      transaction,
      data,
      await deriveFileKey(driveKey, transaction.getTag(EntityTag.fileId)),
    );

Future<Map<String, dynamic>> _decryptEntityJson(
        TransactionCommonMixin transaction,
        Uint8List data,
        KeyParameter key) async =>
    json.decode(
        utf8.decode(await decryptTransactionData(transaction, data, key)));

Future<Uint8List> decryptTransactionData(
  TransactionCommonMixin transaction,
  Uint8List data,
  KeyParameter key,
) async {
  final cipher = transaction.getTag(EntityTag.cipher);

  if (cipher == Cipher.aes256) {
    final cipherIv = utf8.encode(transaction.getTag(EntityTag.cipherIv));

    final decrypter = GCMBlockCipher(AESFastEngine())
      ..init(false, AEADParameters(key, 16 * 8, cipherIv, null));

    return decrypter.process(data);
  }

  throw ArgumentError();
}

/// Creates a transaction with the provided entity's JSON data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedEntityTransaction(
        Entity entity, KeyParameter key) =>
    createEncryptedTransaction(utf8.encode(json.encode(entity)), key);

/// Creates a transaction with the provided data encrypted along with the appropriate cipher tags.
Future<Transaction> createEncryptedTransaction(
  Uint8List data,
  KeyParameter key,
) async {
  final random = Random.secure();
  final cipherIv =
      Uint8List.fromList(List.generate(96 ~/ 8, (_) => random.nextInt(256)));

  final encrypter = GCMBlockCipher(AESFastEngine())
    ..init(true, AEADParameters(key, 16 * 8, cipherIv, null));

  return Transaction.withBlobData(data: encrypter.process(data))
    ..addTag(EntityTag.contentType, ContentType.octetStream)
    ..addTag(EntityTag.cipher, Cipher.aes256)
    ..addTag(
      EntityTag.cipherIv,
      utils.encodeBytesToBase64(cipherIv),
      valueToBase64: false,
    );
}
