import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';

const keyByteLength = 256 ~/ 8;
final _uuid = Uuid();

final pbkdf2 = Pbkdf2(
  macAlgorithm: Hmac(sha256),
  iterations: 100000,
  bits: 256,
);
final hkdf = Hkdf(Hmac(sha256));

Future<ProfileKeyDerivationResult> deriveProfileKey(String password,
    [Nonce salt]) async {
  salt ??= Nonce.randomBytes(128 ~/ 8);

  final keyBytes = await pbkdf2.deriveBits(
    utf8.encode(password),
    nonce: salt,
  );

  return ProfileKeyDerivationResult(SecretKey(keyBytes), salt);
}

Future<SecretKey> deriveDriveKey(
  Wallet wallet,
  String driveId,
  String password,
) async {
  final walletSignature = await wallet
      .sign(Uint8List.fromList(utf8.encode('drive') + _uuid.parse(driveId)));

  return hkdf.deriveKey(
    SecretKey(walletSignature.bytes),
    info: utf8.encode(password),
    outputLength: keyByteLength,
  );
}

Future<SecretKey> deriveFileKey(SecretKey driveKey, String fileId) async {
  final fileIdBytes = Uint8List.fromList(_uuid.parse(fileId));

  return hkdf.deriveKey(
    driveKey,
    info: fileIdBytes,
    outputLength: keyByteLength,
  );
}

class ProfileKeyDerivationResult {
  final SecretKey key;
  final Nonce salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}
