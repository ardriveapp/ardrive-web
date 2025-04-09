import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'crypto.dart';

const keyByteLength = 256 ~/ 8;

final pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac(sha256),
  iterations: 100000,
  bits: 256,
);
final hkdf = Hkdf(hmac: Hmac(sha256), outputLength: keyByteLength);
final aesGcm = AesGcm.with256bits();

// TODO: Check if this file is necessary as this seems to be unused
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
