import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/domain/sealed/sealing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/sealed/vectors.dart';

/// The reference vectors (tool/publication/vectors.mjs), run against the
/// Dart port. Shared by the VM test and the browser test, so both the Dart
/// Argon2id and NFC and the browser's (hash-wasm, String.normalize) are held
/// to the same file.
final vectors = jsonDecode(sealedVectorsJson) as Map<String, dynamic>;

Uint8List bytes(String text) => fromB64u(text, what: 'a vector');

String hexOf(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

List<Map<String, dynamic>> listOf(String name) =>
    (vectors[name] as List).cast<Map<String, dynamic>>();

/// An Argon2id that records what it is asked to run.
class SpyArgon2id implements Argon2idKdf {
  SpyArgon2id(this.inner);

  final Argon2idKdf inner;
  final runs = <Argon2Settings>[];

  @override
  Future<Uint8List> derive({
    required List<int> password,
    required List<int> salt,
    required Argon2Settings settings,
  }) {
    runs.add(settings);
    return inner.derive(password: password, salt: salt, settings: settings);
  }
}

/// An Argon2id that can't run, as when the module doesn't load.
class FailingArgon2id implements Argon2idKdf {
  @override
  Future<Uint8List> derive({
    required List<int> password,
    required List<int> salt,
    required Argon2Settings settings,
  }) =>
      Future.error(StateError('Argon2id did not load'));
}

Matcher sealError(SealErrorCode code) =>
    isA<SealError>().having((e) => e.code, 'code', code);

void sealingVectorTests() {
  final sealing = Sealing();

  test('argon2id vectors', () async {
    for (final v in listOf('argon2id')) {
      final kek = await sealing.passwordKek(
        v['password'] as String,
        salt: bytes(v['salt'] as String),
        settings: Argon2Settings(
            m: v['m'] as int, t: v['t'] as int, p: v['p'] as int),
      );
      expect(hexOf(kek), v['kek'], reason: v['name'] as String);
    }
  });

  test('nfc vectors', () {
    for (final v in listOf('nfc')) {
      final input = utf8.decode(fromHex(v['inputUtf8Hex'] as String));
      expect(hexOf(sealing.passwordBytes(input)), v['nfcUtf8Hex'],
          reason: v['name'] as String);
    }
  });

  test('a password typed composed or decomposed is one password', () {
    final argon = listOf('argon2id');
    final composed = argon.firstWhere((v) => v['name'] == 'NFC, composed');
    final decomposed = argon.firstWhere((v) => v['name'] == 'NFC, decomposed');
    expect(composed['passwordUtf8Hex'], isNot(decomposed['passwordUtf8Hex']));
    expect(
      sealing.passwordBytes(decomposed['password'] as String),
      sealing.passwordBytes(composed['password'] as String),
    );
  });

  test('owner key vectors', () async {
    for (final v in listOf('ownerKek')) {
      final kek = await sealing.ownerKek(
          bytes(v['driveKey'] as String), v['publicationId'] as String);
      expect(hexOf(kek), v['kek']);
    }
  });

  test('wrap vectors unwrap, and only under their own publication', () async {
    for (final v in listOf('wrap')) {
      final kek = fromHex(v['kek'] as String);
      final iv = bytes(v['iv'] as String);
      final key = bytes(v['publicationKey'] as String);
      final id = v['publicationId'] as String;
      expect(b64u(await sealing.wrapKey(kek, iv, key, id)), v['wrapped']);
      final wrapped = bytes(v['wrapped'] as String);
      expect(b64u(await sealing.unwrapKey(kek, iv, wrapped, id)),
          v['publicationKey']);
      await expectLater(
        sealing.unwrapKey(
            kek, iv, wrapped, '00000000-0000-4000-8000-000000000000'),
        throwsA(sealError(SealErrorCode.noMatch)),
      );
    }
  });

  test('sealed associated data vectors', () {
    for (final v in listOf('sealedAad')) {
      final config = jsonDecode(v['publicationJson'] as String) as Map;
      expect(hexOf(utf8.encode(sealedAad(config))), v['aadUtf8Hex'],
          reason: v['name'] as String);
    }
  });

  test('each page opens by link, typed key, password and owner', () async {
    for (final v in listOf('pages')) {
      final name = v['name'] as String;
      final config = jsonDecode(v['publicationJson'] as String);
      final sealed = bytes(v['sealed'] as String);
      final expected = jsonDecode(v['sealedPlaintext'] as String);
      final ways = <OpenedVia, Future<OpenedPage> Function()>{
        OpenedVia.link: () => sealing.openPage(
            config: config,
            sealedBytes: sealed,
            linkKey: v['linkKey'] as String),
        OpenedVia.key: () => sealing.openPage(
            config: config, sealedBytes: sealed, input: v['linkKey'] as String),
        OpenedVia.owner: () => sealing.openPage(
            config: config,
            sealedBytes: sealed,
            driveKey: bytes(v['driveKey'] as String)),
        if (v['password'] != null)
          OpenedVia.password: () => sealing.openPage(
              config: config,
              sealedBytes: sealed,
              input: v['password'] as String),
      };
      for (final MapEntry(key: via, value: open) in ways.entries) {
        final opened = await open();
        expect(opened.via, via, reason: '$name via ${via.name}');
        expect(opened.block.json, expected, reason: '$name via ${via.name}');
        expect(b64u(opened.publicationKey), v['linkKey']);
      }
      expect(canonicalJson(expected), v['sealedPlaintext']);
    }
  });

  test('the writer makes each page byte for byte', () async {
    for (final v in listOf('pages')) {
      final config = jsonDecode(v['publicationJson'] as String) as Map;
      final publicationKey = bytes(v['linkKey'] as String);
      final publicationId = config['publicationId'] as String;
      final slots = <Map<String, Object>>[];
      for (final slot in (config['slots'] as List).cast<Map>()) {
        if (slot['type'] == 'password') {
          slots.add(await sealing.passwordSlot(
            password: v['password'] as String,
            salt: bytes(slot['salt'] as String),
            iv: bytes(slot['iv'] as String),
            settings: Argon2Settings(
                m: slot['m'] as int, t: slot['t'] as int, p: slot['p'] as int),
            publicationKey: publicationKey,
            publicationId: publicationId,
          ));
        } else {
          slots.add(await sealing.ownerSlot(
            driveKey: bytes(v['driveKey'] as String),
            iv: bytes(slot['iv'] as String),
            publicationKey: publicationKey,
            publicationId: publicationId,
          ));
        }
      }
      final viewer = config['viewer'] as Map;
      final json = buildPrivatePublicationJson(
        publicationId: publicationId,
        driveId: config['driveId'] as String,
        folderId: (config['scope'] as Map)['folderId'] as String?,
        owner: config['owner'] as String,
        sealedTxId: (config['sealed'] as Map)['txId'] as String,
        sealedIv: (config['sealed'] as Map)['iv'] as String,
        slots: slots,
        title: config['title'] as String,
        description: config['description'] as String?,
        publishedAt: config['publishedAt'] as String?,
        viewer: (
          release: viewer['release'] as String,
          manifest: viewer['manifest'] as String
        ),
      );
      expect(json, v['publicationJson'], reason: v['name'] as String);

      final sealed = await sealing.sealBlock(
        publicationKey,
        bytes((config['sealed'] as Map)['iv'] as String),
        jsonDecode(v['sealedPlaintext'] as String) as Map<String, Object?>,
        config,
      );
      expect(b64u(sealed), v['sealed'], reason: v['name'] as String);
    }
  });

  test('the block reads as typed fields', () async {
    final v = listOf('pages').first;
    final opened = await sealing.openPage(
      config: jsonDecode(v['publicationJson'] as String),
      sealedBytes: bytes(v['sealed'] as String),
      linkKey: v['linkKey'] as String,
    );
    final plain = jsonDecode(v['sealedPlaintext'] as String) as Map;
    final block = opened.block;
    expect(block.rootFolderId, plain['rootFolderId']);
    expect(block.catalog.txId, (plain['catalog'] as Map)['txId']);
    expect(b64u(block.catalog.key), (plain['catalog'] as Map)['key']);
    expect(block.catalog.tags['Cipher-IV'],
        ((plain['catalog'] as Map)['tags'] as Map)['Cipher-IV']);
    expect(block.files.length, (plain['files'] as Map).length);
    for (final MapEntry(:key, :value) in (plain['files'] as Map).entries) {
      expect(b64u(block.files[key]!), value);
    }
    for (final MapEntry(:key, :value) in (plain['ciphers'] as Map).entries) {
      expect(block.ciphers[key]!.cipher, (value as Map)['cipher']);
      expect(block.ciphers[key]!.iv, value['iv']);
    }
  });

  test('an empty password is refused by the writer', () async {
    await expectLater(
      sealing.passwordKek('',
          salt: List.filled(16, 0),
          settings: const Argon2Settings(m: 8192, t: 1, p: 1)),
      throwsA(sealError(SealErrorCode.invalid)),
    );
  });

  test('a page with no password slot is not opened by a password', () async {
    final v = listOf('pages').firstWhere((p) => p['password'] == null);
    await expectLater(
      sealing.openPage(
        config: jsonDecode(v['publicationJson'] as String),
        sealedBytes: bytes(v['sealed'] as String),
        input: 'correct horse battery staple',
      ),
      throwsA(sealError(SealErrorCode.noMatch)),
    );
  });

  test('refusals, and out-of-bounds slots are never run', () async {
    for (final v in listOf('refusals')) {
      final name = v['name'] as String;
      final spy = SpyArgon2id(Sealing.platformArgon2id());
      await expectLater(
        Sealing(argon2id: spy).openPage(
          config: jsonDecode(v['publicationJson'] as String),
          sealedBytes: bytes(v['sealed'] as String),
          linkKey: v['linkKey'] as String?,
          input: v['input'] as String?,
          driveKey:
              v['driveKey'] == null ? null : bytes(v['driveKey'] as String),
        ),
        throwsA(sealError(v['error'] == 'invalid'
            ? SealErrorCode.invalid
            : SealErrorCode.noMatch)),
        reason: name,
      );
      if (v['outOfBounds'] == true ||
          name.startsWith('only the first') ||
          name.startsWith('an empty password')) {
        expect(spy.runs, isEmpty, reason: name);
      }
    }
  });

  test('a broken link key still lets a password open the page', () async {
    final v = listOf('pages')
        .firstWhere((p) => p['password'] == 'correct horse battery staple');
    for (final linkKey in ['B' * 43, 'short', '${v['linkKey']}x']) {
      final opened = await sealing.openPage(
        config: jsonDecode(v['publicationJson'] as String),
        sealedBytes: bytes(v['sealed'] as String),
        linkKey: linkKey,
        input: v['password'] as String,
      );
      expect(opened.via, OpenedVia.password, reason: linkKey);
    }
  });

  test('a sealed scope nested deep is refused, not a crash', () async {
    final v = listOf('pages')
        .firstWhere((p) => p['password'] == 'correct horse battery staple');
    final config = jsonDecode(v['publicationJson'] as String) as Map;
    final deep = '${'[' * 100000}${']' * 100000}';
    final text = (v['sealedPlaintext'] as String)
        .replaceFirst(RegExp(r'"folderId":"[^"]+"'), '"folderId":$deep');
    final sealed = await sealing.sealPlaintext(
      bytes(v['linkKey'] as String),
      bytes((config['sealed'] as Map)['iv'] as String),
      utf8.encode(text),
      config,
    );
    await expectLater(
      sealing.openPage(
          config: config, sealedBytes: sealed, linkKey: v['linkKey'] as String),
      throwsA(sealError(SealErrorCode.invalid)),
    );
  });

  test('when Argon2id fails, the owner slot still opens the page', () async {
    final v = listOf('pages')
        .firstWhere((p) => p['password'] == 'correct horse battery staple');
    final broken = Sealing(argon2id: FailingArgon2id());
    final config = jsonDecode(v['publicationJson'] as String);
    final sealed = bytes(v['sealed'] as String);
    final opened = await broken.openPage(
      config: config,
      sealedBytes: sealed,
      input: v['password'] as String,
      driveKey: bytes(v['driveKey'] as String),
    );
    expect(opened.via, OpenedVia.owner);
    // With nothing else to try, the failure itself is thrown: the password
    // may have been right, so this is not "that didn't open it".
    await expectLater(
      broken.openPage(
          config: config, sealedBytes: sealed, input: v['password'] as String),
      throwsA(isA<StateError>()),
    );
  });

  test('size caps', () async {
    final v = listOf('pages').first;
    final text = v['publicationJson'] as String;
    final padded = text.replaceFirst(
        '"title"', '"pad": "${'x' * maxPublicationJsonBytes}",\n  "title"');
    expect(() => parsePublicationText(padded),
        throwsA(sealError(SealErrorCode.invalid)));
    expect(parsePublicationText(text), jsonDecode(text));
    await expectLater(
      sealing.openPage(
        config: jsonDecode(text),
        sealedBytes: Uint8List(maxSealedBytes + 1),
        linkKey: v['linkKey'] as String,
      ),
      throwsA(sealError(SealErrorCode.invalid)),
    );
  });

  test('keys have one spelling', () {
    final key = b64u(List.generate(32, (i) => i * 7 + 3));
    expect(looksLikeKey(key), isTrue);
    expect(fromB64u(key, bytes: 32, what: 'k'), hasLength(32));
    expect(() => fromB64u('$key=', bytes: 32, what: 'k'),
        throwsA(isA<SealError>()));
    // The last character of 32 bytes carries two unused bits: setting one
    // decodes to the same bytes, and must still be refused.
    const alphabet =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final last = alphabet.indexOf(key[key.length - 1]);
    final loose = key.substring(0, key.length - 1) + alphabet[last ^ 1];
    expect(
        () => fromB64u(loose, bytes: 32, what: 'k'), throwsA(isA<SealError>()));
    expect(keyFrom(loose), isNull);
    // 45 characters: no whole number of bytes.
    expect(() => fromB64u('${key}AA', what: 'k'), throwsA(isA<SealError>()));
    expect(looksLikeKey('correct horse battery staple'), isFalse);
  });

  test('canonical JSON sorts keys at every depth', () {
    expect(
      canonicalJson({
        'b': [
          {'d': 1, 'c': 2.0},
        ],
        'a': 'x',
      }),
      '{"a":"x","b":[{"c":2,"d":1}]}',
    );
    expect(() => canonicalJson(0.5), throwsArgumentError);
  });

  test('a whole number written as 3.0 reads as 3, as in JavaScript', () {
    final v = listOf('pages').first;
    final text = (v['publicationJson'] as String)
        .replaceFirst('"version": 3', '"version": 3.0')
        .replaceFirst('"t": 1,', '"t": 1.0,');
    final page = readPrivatePublication(jsonDecode(text));
    expect(page.passwordSlot, isNotNull);
    expect(page.passwordSlot!.settings.t, 1);
  });
}
