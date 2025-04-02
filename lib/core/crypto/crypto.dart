import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/entity.dart';
import 'package:ardrive/services/services.dart';
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
    String signatureType,
  ) async {
    final message =
        Uint8List.fromList(utf8.encode('drive') + Uuid.parse(driveId));

    final Uint8List walletSignature;

    if (signatureType == '1') {
      walletSignature = await wallet.sign(message);
    } else if (signatureType == '2') {
      final owner = await wallet.getOwner();
      final dataItem = DataItem.withBlobData(data: message, owner: owner);
      dataItem.addTag('Action', 'Generate-Signature-V2');
      try {
        walletSignature = await wallet.signDataItem(dataItem);
      } catch (e) {
        throw Exception('Failed to sign data item: $e');
      }
    } else {
      throw Exception('Invalid signature type: $signatureType');
    }

    final key = hkdf.deriveKey(
      secretKey: SecretKey(walletSignature),
      info: utf8.encode(password),
      nonce: Uint8List(1),
    );

    return key;
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

      if (cipher == null || cipherIvTag == null) {
        throw MissingCipherTagException(
          corruptedDataAppVersion: transaction.getTag(EntityTag.appVersion),
          corruptedTransactionId: transaction.id,
        );
      }

      final cipherIv = utils.decodeBase64ToBytes(cipherIvTag);

      final keyData = Uint8List.fromList(await key.extractBytes());

      Uint8List decryptedData;

      if (cipher == Cipher.aes256ctr) {
        final stream = await decryptTransactionDataStream(
          cipher,
          cipherIv,
          Stream.fromIterable([data]),
          keyData,
          data.length,
        );

        final bytes = await concatenateUint8ListStream(stream);

        decryptedData = bytes;
      } else if (cipher == Cipher.aes256gcm) {
        final secretBox = secretBoxFromDataWithMacConcatenation(
          data,
          nonce: cipherIv,
        );

        final decryptedDataAsListInt = await aesGcm.decrypt(
          secretBox,
          secretKey: key,
        );

        decryptedData = Uint8List.fromList(decryptedDataAsListInt);
      } else {
        throw UnknownCipherException(
          corruptedDataAppVersion: transaction.getTag(EntityTag.appVersion),
          corruptedTransactionId: transaction.id,
        );
      }

      final jsonStr = utf8.decode(decryptedData);
      final jsonMap = json.decode(jsonStr);

      return jsonMap;
    } catch (e) {
      if (e is ArDriveDecryptionException) {
        rethrow;
      }

      /// Unknow error
      throw TransactionDecryptionException(
        corruptedDataAppVersion: transaction.getTag(EntityTag.appVersion),
        corruptedTransactionId: transaction.id,
      );
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
      throw MissingCipherTagException(
        corruptedDataAppVersion: transaction.getTag(EntityTag.appVersion),
        corruptedTransactionId: transaction.id,
      );
    }

    final decryptedData =
        await decryptTransactionData(cipher, cipherIvTag, data, key);

    return decryptedData;
  }

  /// Creates a transaction with the provided entity's JSON data encrypted along with the appropriate cipher tags.
  Future<Transaction> createEncryptedEntityTransaction(
          Entity entity, SecretKey key) =>
      createEncryptedTransaction(utf8.encode(json.encode(entity)), key);

  /// Creates a data item with the provided entity's JSON data encrypted along with the appropriate cipher tags.
  Future<DataItem> createEncryptedEntityDataItem(
          Entity entity, SecretKey key) =>
      createEncryptedDataItem(utf8.encode(json.encode(entity)), key);

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

class ProfileKeyDerivationResult {
  final SecretKey key;
  final List<int> salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}
