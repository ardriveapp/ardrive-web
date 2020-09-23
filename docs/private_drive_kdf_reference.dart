import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:convert/convert.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

void main() async {
  final arweave = Arweave();
  final uuid = Uuid();
  final wallet = await arweave.wallets.generate();

  final data = utf8.encode('<cool user data>');

  final keyByteLength = 256 ~/ 8;

  // Derive a drive key from the user's provided password
  // and their drive id signed with their wallet.
  //
  // We use a signature from the user's wallet in anticipation of a future
  // where we don't have access to the user's private key.
  // This signature must be generated using RSA-PSS/SHA-256 without a salt for consistency.
  //
  // There's no need to salt here since the drive id will ensure that no two drives have
  // the same key even if the user reuses a password.
  final driveIdBytes = uuid.parse('<drive uuid>');
  final walletSignature = await wallet
      .sign(Uint8List.fromList(utf8.encode('drive') + driveIdBytes));
  final password = '<password provided by user>';

  final driveKdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(walletSignature.bytes, keyByteLength));

  final driveKeyOuput = Uint8List(keyByteLength);
  driveKdf.deriveKey(utf8.encode(password), 0, driveKeyOuput, 0);

  final driveKey = KeyParameter(driveKeyOuput);

  // Derive a file key from the user's drive key and the file id.
  // We don't salt here since the file id is already random enough but
  // we can salt in the future in cases where the user might want to revoke a file key they shared.
  final fileIdBytes = Uint8List.fromList(List.filled(keyByteLength, 0));

  final fileKdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(driveKey.key, keyByteLength));

  final fileKeyOutput = Uint8List(keyByteLength);
  fileKdf.deriveKey(fileIdBytes, 0, fileKeyOutput, 0);

  final fileKey = KeyParameter(fileKeyOutput);

  // Encrypt the data using AES256-GCM using a 96-bit IV as recommended.
  // No need to provide any additional data.
  // See https://crypto.stackexchange.com/questions/35727/does-aad-make-gcm-encryption-more-secure
  final iv = Uint8List(96 ~/ 8);
  final additionalData = Uint8List.fromList([]);

  final params = AEADParameters(fileKey, 16 * 8, iv, additionalData);

  final encrypter = GCMBlockCipher(AESFastEngine())..init(true, params);

  final encryptedData = encrypter.process(data);

  // Encrypted data can then be decrypted using the derived file key and publicly available IV.
  final decrypter = GCMBlockCipher(AESFastEngine())..init(false, params);

  final decryptedData = decrypter.process(encryptedData);

  print(utf8.decode(decryptedData));
  print(hex.encode(driveKey.key));
  print(hex.encode(fileKey.key));
}
