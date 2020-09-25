import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

import 'utils.dart';

const keyByteLength = 256 ~/ 8;
final _uuid = Uuid();

class CipherKey extends KeyParameter {
  CipherKey(Uint8List key) : super(key);
}

Future<ProfileKeyDerivationResult> deriveProfileKey(String password,
    [Uint8List salt]) async {
  salt ??= generateRandomBytes(128 ~/ 8);

  final kdf = PBKDF2KeyDerivator(HMac.withDigest(SHA256Digest()))
    ..init(Pbkdf2Parameters(salt, 20000, keyByteLength));

  final keyOutput = Uint8List(keyByteLength);
  kdf.deriveKey(utf8.encode(password), 0, keyOutput, 0);

  return ProfileKeyDerivationResult(CipherKey(keyOutput), salt);
}

Future<CipherKey> deriveDriveKey(
  Wallet wallet,
  String driveId,
  String password,
) async {
  final walletSignature = await wallet
      .sign(Uint8List.fromList(utf8.encode('drive') + _uuid.parse(driveId)));
  return _deriveKeyFromBytes(walletSignature.bytes, utf8.encode(password));
}

Future<CipherKey> deriveFileKey(CipherKey driveKey, String fileId) async {
  final fileIdBytes = Uint8List.fromList(_uuid.parse(fileId));
  return _deriveKeyFromBytes(driveKey.key, fileIdBytes);
}

Future<CipherKey> _deriveKeyFromBytes(
  Uint8List ikm,
  Uint8List data,
) async {
  final kdf = HKDFKeyDerivator(SHA256Digest())
    ..init(HkdfParameters(ikm, keyByteLength));

  final keyOutput = Uint8List(keyByteLength);
  kdf.deriveKey(data, 0, keyOutput, 0);

  return CipherKey(keyOutput);
}

class ProfileKeyDerivationResult {
  final CipherKey key;
  final Uint8List salt;

  ProfileKeyDerivationResult(this.key, this.salt);
}
