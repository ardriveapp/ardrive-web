import 'dart:convert';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';

const keyByteLength = 256 ~/ 8;
final _uuid = Uuid();

class CipherKey extends KeyParameter {
  CipherKey(Uint8List key) : super(key);
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
  final fileIdBytes = _uuid.parse(fileId);
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
