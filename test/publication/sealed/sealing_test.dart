import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sealing_vectors.dart';

/// The Dart Argon2id and NFC (unorm), as tests and mobile run them. The
/// browser's are in sealing_browser_test.dart.
void main() {
  sealingVectorTests();

  test("the Dart Argon2id matches RFC 9106's own vector", () async {
    final v = vectors['argon2idRfc9106'] as Map<String, dynamic>;
    final key = await DartArgon2id(
      parallelism: v['p'] as int,
      memory: v['m'] as int,
      iterations: v['t'] as int,
      hashLength: v['tagLength'] as int,
    ).deriveKey(
      secretKey: SecretKey(fromHex(v['password'] as String)),
      nonce: fromHex(v['salt'] as String),
      optionalSecret: fromHex(v['secret'] as String),
      associatedData: fromHex(v['associatedData'] as String),
    );
    expect(hexOf(await key.extractBytes()), v['tag']);
  });

  test('the Dart copy of the vectors matches vectors.json', () {
    final json = File('test/publication/fixtures/sealed/vectors.json')
        .readAsStringSync();
    expect(vectors, jsonDecode(json));
  });

  test('the script loader names the vendored Argon2id file', () {
    final loader = File('web/js/lazy_loader.js').readAsStringSync();
    final path =
        RegExp(r"async function loadArgon2\(\)[^}]*'\./(js/hash-wasm/[^']+)'")
            .firstMatch(loader)
            ?.group(1);
    expect(path, isNotNull);
    expect(File('web/$path').existsSync(), isTrue, reason: path);
  });
}
