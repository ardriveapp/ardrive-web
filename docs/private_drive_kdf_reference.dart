// @dart=2.9

import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
// ignore: depend_on_referenced_packages
import 'package:convert/convert.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

void main() async {
  const keyByteLength = 256 ~/ 8;
  final kdf = Hkdf(hmac: Hmac(Sha256()), outputLength: keyByteLength);

  final wallet = await Wallet.generate();

  final data = utf8.encode('<cool user data>');

  // Derive a drive key from the user's provided password
  // and their drive id signed with their wallet.
  //
  // We use a signature from the user's wallet in anticipation of a future
  // where we don't have access to the user's private key.
  // This signature must be generated using RSA-PSS/SHA-256 without a salt for consistency.
  //
  // There's no need to salt here since the drive id will ensure that no two drives have
  // the same key even if the user reuses a password.
  final driveIdBytes = Uuid.parse('<drive uuid>');
  final walletSignature = await wallet
      .sign(Uint8List.fromList(utf8.encode('drive') + driveIdBytes));
  const password = '<password provided by user>';

  final driveKey = await kdf.deriveKey(
    secretKey: SecretKey(walletSignature),
    info: utf8.encode(password),
    nonce: Uint8List(1),
  );

  // Derive a file key from the user's drive key and the file id.
  // We don't salt here since the file id is already random enough but
  // we can salt in the future in cases where the user might want to revoke a file key they shared.
  final fileIdBytes = Uint8List.fromList(Uuid.parse('<file uuid>'));

  final fileKey = await kdf.deriveKey(
    secretKey: driveKey,
    info: fileIdBytes,
    nonce: Uint8List(1),
  );

  // Encrypt the data using AES256-GCM using a 96-bit IV as recommended.
  // No need to provide any additional data.
  // See https://crypto.stackexchange.com/questions/35727/does-aad-make-gcm-encryption-more-secure
  final aesGcm = AesGcm.with256bits();

  final encryptedData = await aesGcm.encrypt(
    data,
    secretKey: fileKey,
  );

  // Encrypted data can then be decrypted using the derived file key and publicly available IV.
  final decryptedData = await aesGcm.decrypt(encryptedData, secretKey: fileKey);

  print(utf8.decode(decryptedData));
  print(hex.encode(await driveKey.extractBytes()));
  print(hex.encode(await fileKey.extractBytes()));
}
