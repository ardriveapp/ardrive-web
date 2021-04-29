import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

import 'crypto.dart';

const keyByteLength = 256 ~/ 8;
final _uuid = Uuid();

final pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac(sha256),
  iterations: 100000,
  bits: 256,
);
final hkdf = Hkdf(hmac: Hmac(sha256), outputLength: keyByteLength);

Future<ProfileKeyDerivationResult> deriveProfileKey(String password,
    [List<int> salt]) async {
  salt ??= aesGcm.newNonce();

  final profileKey = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(password)),
    nonce: salt,
  );

  return ProfileKeyDerivationResult(profileKey, salt);
}

Future<SecretKey> deriveDriveKey(
  Future<Uint8List> Function(Uint8List message) getWalletSignature,
  String driveId,
  String password,
) async {
  final message =
      Uint8List.fromList(utf8.encode('drive') + _uuid.parse(driveId));
  final walletSignature = await getWalletSignature(message);
  print(walletSignature);
  return hkdf.deriveKey(
    secretKey: SecretKey(walletSignature),
    info: utf8.encode(password),
    nonce: Uint8List(0),
  );
}

Future<SecretKey> deriveFileKey(SecretKey driveKey, String fileId) async {
  final fileIdBytes = Uint8List.fromList(_uuid.parse(fileId));

  return hkdf.deriveKey(
    secretKey: driveKey,
    info: fileIdBytes,
    nonce: Uint8List(0),
  );
}

class ProfileKeyDerivationResult {
  final SecretKey key;
  final List<int> salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}
