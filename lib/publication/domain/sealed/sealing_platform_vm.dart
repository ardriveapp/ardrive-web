import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import 'seal_codec.dart';
import 'sealing.dart';

/// Off the web (tests, mobile): Argon2id in Dart, and unorm's NFC.
Argon2idKdf argon2id() => _DartArgon2id();

String nfc(String text) => unorm.nfc(text);

class _DartArgon2id implements Argon2idKdf {
  @override
  Future<Uint8List> derive({
    required List<int> password,
    required List<int> salt,
    required Argon2Settings settings,
  }) async {
    final key = await DartArgon2id(
      parallelism: settings.p,
      memory: settings.m,
      iterations: settings.t,
      hashLength: keyBytes,
    ).deriveKey(secretKey: SecretKey(password), nonce: salt);
    return Uint8List.fromList(await key.extractBytes());
  }
}
