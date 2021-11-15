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
    // This was an empty Uint8List(0), but due to the deferring implmentations of web crypto and dart-vm 
    // we have to add a non empty nonce so that the function works, otherwise this will fail on dart-vm (tests and mobile)
    // However this works with no noticable issues on mobile, so there's no risk.
    nonce: Uint8List(1),
  );
}

Future<SecretKey> deriveFileKey(SecretKey driveKey, String fileId) async {
  final fileIdBytes = Uint8List.fromList(Uuid.parse(fileId));

  return hkdf.deriveKey(
    secretKey: driveKey,
    info: fileIdBytes,
    // This was an empty Uint8List(0), but due to the deferring implmentations of web crypto and dart-vm 
    // we have to add a non empty nonce so that the function works, otherwise this will fail on dart-vm (tests and mobile)
    nonce: Uint8List(1),
  );
}

class ProfileKeyDerivationResult {
  final SecretKey key;
  final List<int> salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}
