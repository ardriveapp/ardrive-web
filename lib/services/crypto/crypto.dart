import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import '../../repositories/repositories.dart';

const keyByteLength = 256 ~/ 8;
final _uuid = Uuid();

Future<Uint8List> decryptDriveEntityData(TransactionCommonMixin transaction,
        Uint8List data, KeyParameter driveKey) =>
    _decryptTransactionData(transaction, data, driveKey);

Future<Uint8List> decryptFolderEntityData(TransactionCommonMixin transaction,
        Uint8List data, KeyParameter driveKey) =>
    _decryptTransactionData(transaction, data, driveKey);

Future<Uint8List> decryptFileEntityData(
    TransactionCommonMixin transaction, Uint8List data, KeyParameter driveKey) {
  final fileIdBytes = _uuid.parse(
      transaction.tags.firstWhere((t) => t.name == EntityTag.fileId).value);

  final fileKdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(driveKey.key, keyByteLength));

  final fileKeyOutput = Uint8List(keyByteLength);
  fileKdf.deriveKey(fileIdBytes, 0, fileKeyOutput, 0);

  final fileKey = KeyParameter(fileKeyOutput);

  return _decryptTransactionData(transaction, data, fileKey);
}

Future<Uint8List> _decryptTransactionData(
  TransactionCommonMixin transaction,
  Uint8List data,
  KeyParameter key,
) async {
  final cipher =
      transaction.tags.firstWhere((t) => t.name == EntityTag.cipher).value;

  if (cipher == Cipher.aes256) {
    final cipherIv =
        transaction.tags.firstWhere((t) => t.name == EntityTag.cipherIv).value;

    final decrypter = GCMBlockCipher(AESFastEngine())
      ..init(false, AEADParameters(key, 16 * 8, utf8.encode(cipherIv), null));

    return decrypter.process(data);
  }

  throw ArgumentError();
}
