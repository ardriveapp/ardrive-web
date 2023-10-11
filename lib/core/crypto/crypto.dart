import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/entity.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:uuid/uuid.dart';

const keyByteLength = 256 ~/ 8;

final sha256 = Sha256();

final aesGcm = AesGcm.with256bits();

final pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac(sha256),
  iterations: 100000,
  bits: 256,
);

final hkdf = Hkdf(hmac: Hmac(sha256), outputLength: keyByteLength);

// TODO: Decouple this class from the TransactionCommonMixin, Transaction, and DataItem classes.
// and implement it on the `ardrive_crypto` package.

class ArDriveCrypto {
  Future<ProfileKeyDerivationResult> deriveProfileKey(String password,
      [List<int>? salt]) async {
    salt ??= aesGcm.newNonce();

    final profileKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    return ProfileKeyDerivationResult(profileKey, salt);
  }

  Future<SecretKey> deriveDriveKey(
    Wallet wallet,
    String driveId,
    String password,
  ) async {
    final message =
        Uint8List.fromList(utf8.encode('drive') + Uuid.parse(driveId));
    final walletSignature = await wallet.sign(message);
    return hkdf.deriveKey(
      secretKey: SecretKey(walletSignature),
      info: utf8.encode(password),
      nonce: Uint8List(1),
    );
  }

  Future<SecretKey> deriveFileKey(SecretKey driveKey, String fileId) async {
    final fileIdBytes = Uint8List.fromList(Uuid.parse(fileId));

    return hkdf.deriveKey(
      secretKey: driveKey,
      info: fileIdBytes,
      nonce: Uint8List(1),
    );
  }

  /// Returns a [SecretBox] that is compatible with our past use of AES-GCM where the cipher text
  /// was appended with the MAC and the nonce was stored separately.
  SecretBox secretBoxFromDataWithMacConcatenation(
    Uint8List data, {
    int macByteLength = 16,
    required Uint8List nonce,
  }) =>
      SecretBox(
        Uint8List.sublistView(data, 0, data.lengthInBytes - macByteLength),
        mac: Mac(
            Uint8List.sublistView(data, data.lengthInBytes - macByteLength)),
        nonce: nonce,
      );

  /// Decrypts the provided transaction details and data into JSON using the provided key.
  ///
  /// Throws a [TransactionDecryptionException] if decryption fails.
  Future<Map<String, dynamic>?> decryptEntityJson(
    TransactionCommonMixin transaction,
    Uint8List data,
    SecretKey key,
  ) async {
    try {
      final cipher = transaction.getTag(EntityTag.cipher);
      final cipherIvTag = transaction.getTag(EntityTag.cipherIv);

      logger.d('starting decryption');

      if (cipher == null || cipherIvTag == null) {
        throw TransactionDecryptionException();
      }

      logger.d('cipher: $cipher');

      final cipherIv = utils.decodeBase64ToBytes(cipherIvTag);

      final keyData = Uint8List.fromList(await key.extractBytes());

      final decryptedData = await decryptTransactionDataStream(
        cipher,
        cipherIv,
        Stream.fromIterable([data]),
        keyData,
        data.length,
      );

      final bytes = await streamToUint8List(decryptedData);
      logger.d('decryptedData: $bytes');

      final jsonStr = utf8.decode(bytes);

      logger.d('json str: $jsonStr');

      final jsonMap = json.decode(jsonStr);

      logger.d('json map: $jsonMap');

      return jsonMap;
    } catch (e) {
      logger.e('Failed to decrypt entity json', e);
      throw TransactionDecryptionException();
    }
  }

  /// Decrypts the provided transaction details and data into JSON using the provided key.
  ///
  /// Throws a [TransactionDecryptionException] if decryption fails.
  Future<Uint8List> decryptDataFromTransaction(
    TransactionCommonMixin transaction,
    Uint8List data,
    SecretKey key,
  ) async {
    final cipher = transaction.getTag(EntityTag.cipher);
    final cipherIvTag = transaction.getTag(EntityTag.cipherIv);

    if (cipher == null || cipherIvTag == null) {
      throw TransactionDecryptionException();
    }

    final decryptedData =
        await decryptTransactionData(cipher, cipherIvTag, data, key);

    return decryptedData;
  }

  /// Creates a transaction with the provided entity's JSON data encrypted along with the appropriate cipher tags.
  Future<Transaction> createEncryptedEntityTransaction(
          Entity entity, SecretKey key) =>
      createEncryptedTransaction(
          utf8.encode(json.encode(entity)) as Uint8List, key);

  /// Creates a data item with the provided entity's JSON data encrypted along with the appropriate cipher tags.
  Future<DataItem> createEncryptedEntityDataItem(
          Entity entity, SecretKey key) =>
      createEncryptedDataItem(
          utf8.encode(json.encode(entity)) as Uint8List, key);

  /// Creates a [Transaction] with the provided data encrypted along with the appropriate cipher tags.
  /// TODO: remove it as we won't use it anymore
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
}

class TransactionDecryptionException implements Exception {}

class ProfileKeyDerivationResult {
  final SecretKey key;
  final List<int> salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}

Future<Uint8List> streamToUint8List(Stream<Uint8List> stream) async {
  List<Uint8List> collectedData = await stream.toList();
  int totalLength =
      collectedData.fold(0, (prev, element) => prev + element.length);

  final result = Uint8List(totalLength);
  int offset = 0;

  for (var data in collectedData) {
    result.setRange(offset, offset + data.length, data);
    offset += data.length;
  }

  return result;
}
