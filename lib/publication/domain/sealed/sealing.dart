import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'seal_codec.dart';
import 'sealing_platform_vm.dart'
    if (dart.library.html) 'sealing_platform_web.dart' as platform;

/// Argon2id (RFC 9106, version 0x13) with a 32-byte output, no secret and
/// no associated data.
abstract class Argon2idKdf {
  Future<Uint8List> derive({
    required List<int> password,
    required List<int> salt,
    required Argon2Settings settings,
  });
}

/// The keys and encryption of a private drive or folder page. A port of
/// `tool/publication/seal.mjs`; the formats are in `seal_codec.dart`.
///
/// Randomness (keys, salts, IVs) is always passed in, so every output is
/// fixed for fixed inputs and can be checked against the vectors.
class Sealing {
  Sealing({Argon2idKdf? argon2id, String Function(String)? nfc})
      : _argon2id = argon2id ?? platform.argon2id(),
        _nfc = nfc ?? platform.nfc;

  /// This platform's Argon2id: hash-wasm in a browser, Dart elsewhere.
  static Argon2idKdf platformArgon2id() => platform.argon2id();

  final Argon2idKdf _argon2id;
  final String Function(String) _nfc;

  static final _aesGcm = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyBytes);

  /// The password, NFC-normalised, as UTF-8: "é" typed either way is one
  /// password.
  Uint8List passwordBytes(String password) =>
      Uint8List.fromList(utf8.encode(_nfc(password)));

  Future<Uint8List> passwordKek(
    String password, {
    required List<int> salt,
    required Argon2Settings settings,
  }) {
    checkArgon2Settings(settings.m, settings.t, settings.p);
    final bytes = passwordBytes(password);
    // Not every Argon2id takes an empty message (hash-wasm doesn't), and an
    // empty password protects nothing.
    if (bytes.isEmpty) {
      return Future.error(const SealError(
          SealErrorCode.invalid, 'a password is at least one character'));
    }
    return _argon2id.derive(
      password: bytes,
      salt: salt,
      settings: settings,
    );
  }

  /// HKDF-SHA256 (RFC 5869) over the drive key, empty salt. A key made for
  /// this one publication: the drive key itself never wraps anything.
  Future<Uint8List> ownerKek(List<int> driveKey, String publicationId) async {
    if (driveKey.length != keyBytes) {
      throw const SealError(SealErrorCode.invalid, 'a drive key is 32 bytes');
    }
    final key = await _hkdf.deriveKey(
      secretKey: SecretKey(driveKey),
      // RFC 5869 reads an absent salt as HashLen zero bytes; this library
      // refuses an empty one, and HMAC pads either to the same block.
      nonce: Uint8List(32),
      info: utf8.encode(ownerInfoPrefix + publicationId),
    );
    return Uint8List.fromList(await key.extractBytes());
  }

  Future<Uint8List> _encrypt(
    List<int> key,
    List<int> iv,
    List<int> plaintext,
    String aad,
  ) async {
    final box = await _aesGcm.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: iv,
      aad: utf8.encode(aad),
    );
    return Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
  }

  Future<Uint8List> _decrypt(
    List<int> key,
    List<int> iv,
    Uint8List sealed,
    String aad,
  ) async {
    if (sealed.length < tagBytes) {
      throw const SealError(SealErrorCode.noMatch, 'ciphertext is too short');
    }
    final split = sealed.length - tagBytes;
    try {
      final plain = await _aesGcm.decrypt(
        SecretBox(
          Uint8List.sublistView(sealed, 0, split),
          nonce: iv,
          mac: Mac(Uint8List.sublistView(sealed, split)),
        ),
        secretKey: SecretKey(key),
        aad: utf8.encode(aad),
      );
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const SealError(
          SealErrorCode.noMatch, 'the key does not open this');
    }
  }

  /// AES-256-GCM of the publication key, bound to the publication by its
  /// associated data.
  Future<Uint8List> wrapKey(
    List<int> kek,
    List<int> iv,
    List<int> publicationKey,
    String publicationId,
  ) =>
      _encrypt(kek, iv, publicationKey, slotAadPrefix + publicationId);

  Future<Uint8List> unwrapKey(
    List<int> kek,
    List<int> iv,
    Uint8List wrapped,
    String publicationId,
  ) async {
    final key = await _decrypt(kek, iv, wrapped, slotAadPrefix + publicationId);
    if (key.length != keyBytes) {
      throw const SealError(
          SealErrorCode.invalid, 'a wrapped key must be 32 bytes');
    }
    return key;
  }

  Future<Map<String, Object>> passwordSlot({
    required String password,
    required List<int> salt,
    required List<int> iv,
    required Argon2Settings settings,
    required List<int> publicationKey,
    required String publicationId,
  }) async {
    final kek = await passwordKek(password, salt: salt, settings: settings);
    return {
      'type': 'password',
      'kdf': 'argon2id',
      'salt': b64u(salt),
      'm': settings.m,
      't': settings.t,
      'p': settings.p,
      'cipher': sealCipher,
      'iv': b64u(iv),
      'wrapped': b64u(await wrapKey(kek, iv, publicationKey, publicationId)),
    };
  }

  Future<Map<String, Object>> ownerSlot({
    required List<int> driveKey,
    required List<int> iv,
    required List<int> publicationKey,
    required String publicationId,
  }) async {
    final kek = await ownerKek(driveKey, publicationId);
    return {
      'type': 'owner',
      'kdf': 'hkdf-sha256',
      'cipher': sealCipher,
      'iv': b64u(iv),
      'wrapped': b64u(await wrapKey(kek, iv, publicationKey, publicationId)),
    };
  }

  /// The sealed part's bytes: the block's canonical JSON, bound to its page
  /// by [config], the page's publication.json (only the fields [sealedAad]
  /// reads are needed).
  Future<Uint8List> sealBlock(
    List<int> publicationKey,
    List<int> iv,
    Map<String, Object?> block,
    Map config,
  ) =>
      _encrypt(
        publicationKey,
        iv,
        utf8.encode(canonicalJson(block)),
        sealedAad(config),
      );

  /// Opens a page. [linkKey] is the `k` in the link; [input] is what a
  /// visitor typed (a pasted key or a password); [driveKey] is the owner's.
  /// Tried in that order: link key, typed key, password slot, owner slot.
  ///
  /// Throws [SealError] with [SealErrorCode.noMatch] when nothing opens it,
  /// and [SealErrorCode.invalid] when the page is malformed or a key opens a
  /// block that breaks the rules.
  Future<OpenedPage> openPage({
    required Object? config,
    required Uint8List sealedBytes,
    String? linkKey,
    String? input,
    List<int>? driveKey,
  }) async {
    final page = readPrivatePublication(config);
    if (sealedBytes.length > maxSealedBytes) {
      throw const SealError(
          SealErrorCode.invalid, 'the sealed part is too large');
    }
    final aad = sealedAad(page.config);

    Future<OpenedPage?> attempt(Uint8List key, OpenedVia via) async {
      final Uint8List plain;
      try {
        plain = await _decrypt(key, page.sealedIv, sealedBytes, aad);
      } on SealError catch (e) {
        if (e.code == SealErrorCode.noMatch) return null;
        rethrow;
      }
      final Object? block;
      try {
        block = jsonDecode(utf8.decode(plain, allowMalformed: true));
      } on FormatException {
        throw const SealError(
            SealErrorCode.invalid, 'the sealed block is not JSON');
      }
      return OpenedPage(
        publicationKey: key,
        block: readSealedBlock(block, page.config),
        via: via,
      );
    }

    Future<Uint8List?> unwrapped(
        Uint8List kek, Uint8List iv, Uint8List wrapped) async {
      try {
        return await unwrapKey(kek, iv, wrapped, page.publicationId);
      } on SealError catch (e) {
        if (e.code == SealErrorCode.noMatch) return null;
        rethrow;
      }
    }

    final fromLink = keyFrom(linkKey);
    if (fromLink != null) {
      final opened = await attempt(fromLink, OpenedVia.link);
      if (opened != null) return opened;
    }
    if (input != null) {
      final typed = keyFrom(input);
      if (typed != null) {
        final opened = await attempt(typed, OpenedVia.key);
        if (opened != null) return opened;
      }
      final slot = page.passwordSlot;
      if (slot != null && input.isNotEmpty) {
        final kek =
            await passwordKek(input, salt: slot.salt, settings: slot.settings);
        final key = await unwrapped(kek, slot.iv, slot.wrapped);
        final opened =
            key == null ? null : await attempt(key, OpenedVia.password);
        if (opened != null) return opened;
      }
    }
    final owner = page.ownerSlot;
    if (driveKey != null && owner != null) {
      final kek = await ownerKek(driveKey, page.publicationId);
      final key = await unwrapped(kek, owner.iv, owner.wrapped);
      final opened = key == null ? null : await attempt(key, OpenedVia.owner);
      if (opened != null) return opened;
    }
    throw const SealError(
        SealErrorCode.noMatch, 'nothing given opens this page');
  }
}

enum OpenedVia { link, key, password, owner }

class OpenedPage {
  const OpenedPage({
    required this.publicationKey,
    required this.block,
    required this.via,
  });

  final Uint8List publicationKey;
  final SealedBlock block;
  final OpenedVia via;
}
