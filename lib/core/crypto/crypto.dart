import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/entities/drive_signature.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/entities/entity.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
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

  /// Derives Drive Key:
  ///
  /// v1 - uses signature()
  /// v2 - uses signDataItem()
  ///
  /// ArFS v15 introduced v2 signature type to deal with deprecation of signature()
  /// in Wander. If a v1 Drive is found, this will attempt to first find a stored
  /// v1 drive key on Arweave and decrypt it using v2 drive key. If not found,
  /// will try to use signature() if available.
  ///
  /// Built from [walletSignatureForDrive], [decryptStoredDriveSignature] and
  /// [driveKeyFromSignature], which the unlock path calls one at a time so it
  /// can reuse a signature across passwords. Known-answer tests in
  /// `test/core/crypto/drive_key_derivation_test.dart` hold every one of them
  /// to the keys this has always produced.
  Future<DriveKey> deriveDriveKey(
    Wallet wallet,
    String driveId,
    String password,
    DriveSignatureType signatureType,
    DriveSignatureEntity? driveSignature,
  ) async {
    final info = utf8.encode(password);

    if (signatureType == DriveSignatureType.v1 && driveSignature != null) {
      // stored v1 drive signatures are encrypted with v2 drive key
      final driveKeyV2 = await deriveDriveKey(
          wallet, driveId, password, DriveSignatureType.v2, null);

      final walletSignature =
          await decryptStoredDriveSignature(driveSignature, driveKeyV2.key);

      return driveKeyFromSignature(walletSignature, info, generated: false);
    }

    final walletSignature =
        await walletSignatureForDrive(wallet, driveId, signatureType);

    return driveKeyFromSignature(walletSignature, info, generated: true);
  }

  /// What a wallet signs to make a drive's key: `"drive"` and the drive ID's
  /// 16 bytes.
  Uint8List driveSignatureMessage(String driveId) =>
      Uint8List.fromList(utf8.encode('drive') + Uuid.parse(driveId));

  /// The data item whose signature is [driveId]'s v2 wallet signature:
  /// [driveSignatureMessage] tagged `Action: Drive-Signature-V2`, with no
  /// target or anchor, owned by [owner] (a public key).
  DataItem driveSignatureDataItem(String owner, String driveId) =>
      DataItem.withBlobData(data: driveSignatureMessage(driveId), owner: owner)
        ..addTag('Action', 'Drive-Signature-V2');

  /// Whether [signature] is [owner]'s signature of [driveId]'s v2 item
  /// ([driveSignatureDataItem]): RSA-PSS with a salt of length 0 over the
  /// item's ANS-104 signature data, checked against the public key [owner].
  ///
  /// With no salt there is exactly one valid signature, so one that passes is
  /// the one every ArDrive app derives this drive's key from. A wallet that
  /// salts its signatures, signs another item (another drive's, or with an
  /// anchor of its own, as Keystone does) or returns them out of order fails.
  Future<bool> isDriveSignature({
    required String owner,
    required String driveId,
    required Uint8List signature,
  }) async {
    final signer = _GivenSignature(signature);
    try {
      await driveSignatureDataItem(owner, driveId).sign(signer);
      return await SignatureConfig.arweave
          .verify(signer.signedMessage!, signature, owner);
    } catch (e) {
      logger.w('Could not check a drive signature: $e');
      return false;
    }
  }

  /// Each of [driveIds]' v2 wallet signatures, signed in one Wander approval.
  /// Not checked here: the caller checks each with [isDriveSignature].
  ///
  /// Throws whatever Wander throws, a cancelled prompt included, and a
  /// [StateError] if it returns a different number of signatures.
  Future<List<Uint8List>> batchWalletSignaturesForDrives(
    ArConnectWallet wallet,
    List<String> driveIds,
  ) async {
    final owner = await wallet.getOwner();
    final signatures = await wallet.batchSignDataItems([
      for (final driveId in driveIds) driveSignatureDataItem(owner, driveId),
    ]);

    if (signatures.length != driveIds.length) {
      throw StateError('Wander returned ${signatures.length} signatures for '
          '${driveIds.length} items');
    }

    return signatures;
  }

  /// The wallet's signature for [driveId], the secret half of its key.
  ///
  /// v1 is `wallet.sign` over [driveSignatureMessage]; v2 is the signature of
  /// an ANS-104 data item holding it, tagged `Action: Drive-Signature-V2`,
  /// which is what Wander's `signDataItem` makes. Neither depends on the
  /// password, which is why the unlock path can keep one per drive for the
  /// session and try several passwords against it.
  ///
  /// Throws whatever the wallet throws, a cancelled prompt included.
  Future<Uint8List> walletSignatureForDrive(
    Wallet wallet,
    String driveId,
    DriveSignatureType signatureType,
  ) async {
    final message = driveSignatureMessage(driveId);

    if (signatureType == DriveSignatureType.v1) {
      logger.d('Signing with v1 signature (wallet.sign)');
      try {
        final signature = await wallet.sign(message);
        logger.d('v1 signing successful');
        return signature;
      } catch (e, stackTrace) {
        logger.e('v1 signing failed', e, stackTrace);
        rethrow;
      }
    } else if (signatureType == DriveSignatureType.v2) {
      final dataItem = driveSignatureDataItem(await wallet.getOwner(), driveId);
      final Uint8List signature;
      try {
        if (wallet is ArConnectWallet) {
          logger.d('Signing with v2 signature (wallet.signDataItem)');
          signature = await wallet.signDataItem(dataItem);
        } else {
          logger.d('Signing with v2 signature (DataItem.sign)');
          await dataItem.sign(ArweaveSigner(wallet));
          logger.d('v2 signing successful');
          return utils.decodeBase64ToBytes(dataItem.signature);
        }
      } catch (e, stackTrace) {
        logger.e('v2 signing failed', e, stackTrace);
        throw Exception('Failed to sign data item: $e');
      }

      // A browser wallet signs for us, so its answer is checked before a key
      // is made from it: a key from any other signature never opens again.
      if (!await isDriveSignature(
          owner: dataItem.owner, driveId: driveId, signature: signature)) {
        throw const WalletCantMakeDriveKeysException();
      }
      logger.d('v2 signing successful');
      return signature;
    } else {
      throw Exception('Invalid signature type: $signatureType');
    }
  }

  /// A v1 drive's wallet signature, out of the drive-signature record that
  /// holds it encrypted under the drive's v2 key.
  ///
  /// Throws [SecretBoxAuthenticationError] when [driveKeyV2] is not the key
  /// the record was written with, which for the right wallet means the wrong
  /// password.
  Future<Uint8List> decryptStoredDriveSignature(
    DriveSignatureEntity driveSignature,
    SecretKey driveKeyV2,
  ) =>
      decrypt(driveSignature.data, driveKeyV2,
          utils.decodeBase64ToBytes(driveSignature.cipherIv));

  /// HKDF-SHA256 of [walletSignature] with [info] - the password's bytes -
  /// and no salt: the drive key every ArDrive app derives.
  ///
  /// [info] is bytes rather than the password so the unlock path can also try
  /// the double-encoded form core-js, the CLI and desktop produce for a
  /// non-ASCII password. See `drivePasswordInfos`.
  Future<DriveKey> driveKeyFromSignature(
    Uint8List walletSignature,
    List<int> info, {
    required bool generated,
  }) async {
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(walletSignature),
      info: info,
      nonce: Uint8List(1),
    );

    return DriveKey(key, generated);
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

  /// Decrypts data whose cipher and IV the caller already holds.
  ///
  /// [decryptDataFromTransaction] reads those two values off a transaction it
  /// asks the gateway to describe. A share link carries them for the
  /// transaction it names, so a caller holding one can decrypt without that
  /// lookup - which is the only reason `c` and `iv` are in the link schema.
  ///
  /// Named for what it takes rather than after the top-level
  /// `decryptTransactionData` it delegates to: an unqualified call to a
  /// same-named function from inside this class would resolve to the method
  /// and recurse.
  ///
  /// Throws a [TransactionDecryptionException] if decryption fails.
  Future<Uint8List> decryptDataWithCipher(
    String cipher,
    String cipherIvString,
    Uint8List data,
    SecretKey key,
  ) =>
      decryptTransactionData(cipher, cipherIvString, data, key);

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

  Future<SecretBox> encrypt(Uint8List data, SecretKey key) async {
    final encryptionRes = await aesGcm.encrypt(data.toList(), secretKey: key);
    return encryptionRes;
  }

  Future<Uint8List> decrypt(
      Uint8List data, SecretKey key, Uint8List cipherIv) async {
    final secretBox = secretBoxFromDataWithMacConcatenation(
      data,
      nonce: cipherIv,
    );

    final decryptedDataAsListInt = await aesGcm.decrypt(
      secretBox,
      secretKey: key,
    );

    return Uint8List.fromList(decryptedDataAsListInt);
  }
}

class ProfileKeyDerivationResult {
  final SecretKey key;
  final List<int> salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}

class DriveKey {
  final SecretKey key;
  final bool generated;

  DriveKey(this.key, this.generated);
}

/// The wallet's signature for a drive is not the one a drive key can be made
/// from: it isn't RSA-PSS with no salt over the exact item asked for. Keystone
/// adds an anchor of its own, for one. A key made from it would never open
/// the drive again, so none is made.
class WalletCantMakeDriveKeysException implements Exception {
  const WalletCantMakeDriveKeysException();

  @override
  String toString() => 'WalletCantMakeDriveKeysException';
}

/// A [Signer] that answers with a signature already made, and keeps the
/// message it was asked to sign: the item's signature data.
class _GivenSignature implements Signer {
  _GivenSignature(this._signature);

  final Uint8List _signature;
  Uint8List? signedMessage;

  @override
  SignatureConfig get signatureConfig => SignatureConfig.arweave;

  @override
  Future<Uint8List> sign(Uint8List message, [String? context]) async {
    signedMessage = message;
    return _signature;
  }
}
