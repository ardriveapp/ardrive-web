import 'dart:convert';
import 'dart:typed_data';

/// The formats of a private drive or folder page (publication.json version
/// 3): what is checked, bound and spelled, with no cryptography. The
/// encryption is in `sealing.dart`.
///
/// This is a port of `tool/publication/seal.mjs`, the reference, and is held
/// to it by `test/publication/fixtures/sealed/vectors.json`. Spec:
/// docs/ArweaveFS.md, "Private publications".

/// The publication.json version of a private drive or folder page.
const privatePublicationVersion = 3;

/// The version of the sealed block's JSON, inside the encryption.
const sealedVersion = 1;

const sealCipher = 'AES256-GCM';

/// Argon2id settings: memory [m] in KiB, passes [t], lanes [p].
class Argon2Settings {
  const Argon2Settings({required this.m, required this.t, required this.p});

  final int m;
  final int t;
  final int p;
}

/// What a writer uses until the speed test says otherwise.
const argon2Defaults = Argon2Settings(m: 65536, t: 3, p: 1);

/// A reader never runs a password slot outside these bounds: a page could
/// otherwise ask a visitor's browser for gigabytes. Inclusive.
const argon2MemoryBounds = (8192, 262144);
const argon2PassesBounds = (1, 10);
const argon2LanesBounds = (1, 4);
const argon2SaltBytesBounds = (16, 64);

/// A reader refuses a version 3 publication.json larger than this.
const maxPublicationJsonBytes = 65536;

/// A reader refuses a sealed part larger than this, before decrypting it.
const maxSealedBytes = 32 * 1024 * 1024;

/// The ciphers whose IV a reader checks; any other is ignored and looked up
/// as usual.
const knownDataCiphers = ['AES256-GCM', 'AES256-CTR'];

const keyBytes = 32;
const ivBytes = 12;
const tagBytes = 16;

const slotAadPrefix = 'ArDrive publication slot v1|';
const sealedAadPrefix = 'ArDrive publication sealed v1|';
const ownerInfoPrefix = 'ArDrive publication owner v1|';

enum SealErrorCode {
  /// Malformed: the page or block breaks the format.
  invalid,

  /// Well formed, but what was given doesn't open it.
  noMatch,

  /// A password slot asks for work outside the bounds.
  outOfBounds,
}

class SealError implements Exception {
  const SealError(this.code, this.message);

  final SealErrorCode code;
  final String message;

  @override
  String toString() => 'SealError(${code.name}): $message';
}

Never _invalid(String message) =>
    throw SealError(SealErrorCode.invalid, message);

void _need(bool condition, String message) {
  if (!condition) _invalid(message);
}

/// base64url without padding, as ArFS writes keys and IVs.
String b64u(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');

final _b64uText = RegExp(r'^[A-Za-z0-9_-]*$');

/// [text] as bytes, refusing anything but the one canonical spelling, and
/// any length but [bytes] when given.
Uint8List fromB64u(Object? text, {int? bytes, required String what}) {
  if (text is! String || !_b64uText.hasMatch(text)) {
    _invalid('$what is not base64url');
  }
  final Uint8List out;
  try {
    out = base64Url.decode(base64Url.normalize(text));
  } on FormatException {
    _invalid('$what is not base64url');
  }
  if (bytes != null && out.length != bytes) {
    _invalid('$what must be $bytes bytes');
  }
  if (b64u(out) != text) _invalid('$what is not canonical base64url');
  return out;
}

/// Sorted keys at every depth, no whitespace: one byte string per value.
/// Numbers must be whole; this format has no others.
String canonicalJson(Object? value) {
  if (value is List) return '[${value.map(canonicalJson).join(',')}]';
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(value[k])}').join(',')}}';
  }
  if (value is double) {
    final whole = _wholeNumber(value);
    if (whole == null) {
      throw ArgumentError.value(
          value, 'value', 'canonical JSON has no fractions');
    }
    return '$whole';
  }
  return jsonEncode(value);
}

/// A JSON number that is a whole number, as JavaScript's Number.isInteger
/// sees it: 3 and 3.0 are both 3.
int? _wholeNumber(Object? value) {
  if (value is int) return value;
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

void checkArgon2Settings(Object? m, Object? t, Object? p) {
  for (final (name, value, (lo, hi)) in [
    ('m', m, argon2MemoryBounds),
    ('t', t, argon2PassesBounds),
    ('p', p, argon2LanesBounds),
  ]) {
    final n = _wholeNumber(value);
    if (n == null || n < lo || n > hi) {
      throw SealError(
        SealErrorCode.outOfBounds,
        'argon2id $name=$value is outside $lo..$hi',
      );
    }
  }
}

final _uuid =
    RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
final _txId = RegExp(r'^[A-Za-z0-9_-]{43}$');
final _plainPath = RegExp(r'^[A-Za-z0-9._/-]+$');

bool _isUuid(Object? v) => v is String && _uuid.hasMatch(v);
bool _isTxId(Object? v) => v is String && _txId.hasMatch(v);

/// Letters, digits, '.', '_', '-' and '/'; no leading '/', and no empty,
/// '.' or '..' segment.
bool _isPlainPath(Object? path) =>
    path is String &&
    _plainPath.hasMatch(path) &&
    path.split('/').every((s) => s.isNotEmpty && s != '.' && s != '..');

/// publication.json for a private drive or folder page. Nothing in it is
/// secret: no names, no file count, no keys except wrapped ones.
String buildPrivatePublicationJson({
  required String publicationId,
  required String driveId,
  String? folderId,
  required String owner,
  required String sealedTxId,
  required String sealedIv,
  required List<Map<String, Object>> slots,
  String title = '',
  String? description,
  String? ownerName,
  List<String>? keywords,
  Object? license,
  Map<String, Object?>? images,
  String? publishedAt,
  List<Object?>? names,
  ({String release, String manifest})? viewer,
}) {
  final config = <String, Object?>{
    'version': privatePublicationVersion,
    'publicationId': publicationId,
    'driveId': driveId,
    'scope': folderId != null && folderId.isNotEmpty
        ? {'type': 'folder', 'folderId': folderId}
        : {'type': 'drive'},
    'privacy': 'private',
    'owner': owner,
    if (ownerName != null && ownerName.isNotEmpty) 'ownerName': ownerName,
    'sealed': {
      'path': 'sealed',
      'txId': sealedTxId,
      'cipher': sealCipher,
      'iv': sealedIv,
    },
    'slots': slots,
    'title': title,
    if (description != null && description.isNotEmpty)
      'description': description,
    if (keywords != null && keywords.isNotEmpty) 'keywords': keywords,
    if (license != null) 'license': license,
    if (images != null && images.isNotEmpty) 'images': images,
    if (publishedAt != null && publishedAt.isNotEmpty)
      'publishedAt': publishedAt,
    if (names != null && names.isNotEmpty) 'names': names,
    if (viewer != null)
      'viewer': {'release': viewer.release, 'manifest': viewer.manifest},
  };
  return '${const JsonEncoder.withIndent('  ').convert(config)}\n';
}

/// publication.json's text, size-checked and parsed.
Object? parsePublicationText(String text) {
  _need(
    utf8.encode(text).length <= maxPublicationJsonBytes,
    'publication.json is too large',
  );
  try {
    return jsonDecode(text);
  } on FormatException {
    _invalid('publication.json is not JSON');
  }
}

/// The page's scope with only the keys the spec defines.
Map<String, Object?> _scopeOf(Map scope) => scope['type'] == 'folder'
    ? {'type': 'folder', 'folderId': scope['folderId']}
    : {'type': 'drive'};

/// What the sealed block is bound to, as its associated data: the page's
/// identity and the text everyone sees. A sealed part reused under another
/// drive, owner, scope, title or description does not open.
String sealedAad(Map config) =>
    sealedAadPrefix +
    canonicalJson({
      'description': config['description'] ?? '',
      'driveId': config['driveId'],
      'owner': config['owner'],
      'publicationId': config['publicationId'],
      'scope': _scopeOf(config['scope'] as Map),
      'title': config['title'],
    });

class PasswordSlot {
  const PasswordSlot({
    required this.salt,
    required this.settings,
    required this.iv,
    required this.wrapped,
  });

  final Uint8List salt;
  final Argon2Settings settings;
  final Uint8List iv;
  final Uint8List wrapped;
}

class OwnerSlot {
  const OwnerSlot({required this.iv, required this.wrapped});

  final Uint8List iv;
  final Uint8List wrapped;
}

/// A version 3 publication.json a reader has checked.
class PrivatePublication {
  const PrivatePublication({
    required this.config,
    required this.publicationId,
    required this.sealedIv,
    required this.passwordSlot,
    required this.ownerSlot,
  });

  final Map<String, dynamic> config;
  final String publicationId;
  final Uint8List sealedIv;

  /// The first password slot, or null when there is none or it is
  /// malformed or out of bounds. Such a page still opens by key.
  final PasswordSlot? passwordSlot;

  /// The first owner slot, or null as for [passwordSlot].
  final OwnerSlot? ownerSlot;
}

/// The reader's checks on a version 3 publication.json, beyond JSON
/// parsing. Only the first slot of each type is read; a password slot that
/// is malformed or outside the bounds is never run.
PrivatePublication readPrivatePublication(Object? config) {
  _need(config is Map<String, dynamic>, 'publication.json must be an object');
  config as Map<String, dynamic>;
  _need(config['version'] == privatePublicationVersion, 'version must be 3');
  _need(config['privacy'] == 'private', 'a version 3 page is private');
  _need(_isUuid(config['publicationId']),
      'publicationId must be a lowercase UUID');
  _need(_isUuid(config['driveId']), 'driveId must be a lowercase UUID');
  final scope = config['scope'];
  _need(scope is Map, 'scope must be an object');
  scope as Map;
  if (scope['type'] == 'folder') {
    _need(
        _isUuid(scope['folderId']), 'scope.folderId must be a lowercase UUID');
  } else {
    _need(scope['type'] == 'drive', 'scope.type must be drive or folder');
  }
  _need(_isTxId(config['owner']), 'owner must be an Arweave address');
  _need(config['title'] is String, 'title must be a string, and may be empty');
  _need(
    !config.containsKey('description') || config['description'] is String,
    'description must be a string',
  );
  for (final key in ['rootFolderId', 'snapshot', 'file', 'fileCount']) {
    _need(!config.containsKey(key), 'a private page has no $key');
  }

  final sealed = config['sealed'];
  _need(sealed is Map, 'sealed must be an object');
  sealed as Map;
  _need(_isPlainPath(sealed['path']),
      'sealed.path must be a plain relative path');
  _need(_isTxId(sealed['txId']), 'sealed.txId must be a transaction ID');
  _need(sealed['cipher'] == sealCipher, 'sealed.cipher must be $sealCipher');
  final sealedIv = fromB64u(sealed['iv'], bytes: ivBytes, what: 'sealed.iv');

  final slotList = config['slots'];
  _need(slotList is List, 'slots must be an array');
  final slots = (slotList as List).whereType<Map>().toList();

  PasswordSlot? passwordSlot;
  final p = slots.where((s) => s['type'] == 'password').firstOrNull;
  if (p != null) {
    try {
      _need(p['kdf'] == 'argon2id' && p['cipher'] == sealCipher,
          'unknown password slot');
      checkArgon2Settings(p['m'], p['t'], p['p']);
      final salt = fromB64u(p['salt'], what: 'slot salt');
      if (salt.length < argon2SaltBytesBounds.$1 ||
          salt.length > argon2SaltBytesBounds.$2) {
        throw const SealError(
            SealErrorCode.outOfBounds, 'a slot salt is 16 to 64 bytes');
      }
      passwordSlot = PasswordSlot(
        salt: salt,
        settings: Argon2Settings(
          m: _wholeNumber(p['m'])!,
          t: _wholeNumber(p['t'])!,
          p: _wholeNumber(p['p'])!,
        ),
        iv: fromB64u(p['iv'], bytes: ivBytes, what: 'slot iv'),
        wrapped: fromB64u(p['wrapped'],
            bytes: keyBytes + tagBytes, what: 'slot wrapped'),
      );
    } on SealError {
      passwordSlot = null;
    }
  }

  OwnerSlot? ownerSlot;
  final o = slots.where((s) => s['type'] == 'owner').firstOrNull;
  if (o != null) {
    try {
      _need(o['kdf'] == 'hkdf-sha256' && o['cipher'] == sealCipher,
          'unknown owner slot');
      ownerSlot = OwnerSlot(
        iv: fromB64u(o['iv'], bytes: ivBytes, what: 'slot iv'),
        wrapped: fromB64u(o['wrapped'],
            bytes: keyBytes + tagBytes, what: 'slot wrapped'),
      );
    } on SealError {
      ownerSlot = null;
    }
  }

  return PrivatePublication(
    config: config,
    publicationId: config['publicationId'] as String,
    sealedIv: sealedIv,
    passwordSlot: passwordSlot,
    ownerSlot: ownerSlot,
  );
}

/// The catalog: the Drive State artifact of the page's scope, encrypted
/// under its own [key].
class SealedCatalog {
  const SealedCatalog({
    required this.path,
    required this.txId,
    required this.key,
    required this.tags,
  });

  final String path;
  final String txId;
  final Uint8List key;
  final Map<String, String> tags;
}

/// How one data transaction is encrypted.
class SealedCipher {
  const SealedCipher({required this.cipher, this.iv});

  final String cipher;
  final String? iv;
}

/// The decrypted sealed block, checked against its page.
class SealedBlock {
  const SealedBlock({
    required this.json,
    required this.rootFolderId,
    required this.catalog,
    required this.files,
    required this.ciphers,
  });

  final Map<String, dynamic> json;
  final String rootFolderId;
  final SealedCatalog catalog;

  /// File ID to file key. Its length is the page's file count.
  final Map<String, Uint8List> files;

  /// Data or thumbnail transaction ID to its cipher.
  final Map<String, SealedCipher> ciphers;
}

/// Whether two scopes name the same thing. Compared field by field, never
/// by serialising: a hostile block's folderId may be any JSON, a fraction
/// [canonicalJson] refuses or nesting deep enough to overflow it.
bool _sameScope(Map a, Map b) {
  final x = _scopeOf(a);
  final y = _scopeOf(b);
  return x['type'] == y['type'] &&
      (x['type'] != 'folder' ||
          (_isUuid(x['folderId']) && x['folderId'] == y['folderId']));
}

/// The checks on the decrypted sealed block. It must describe the page it
/// came with.
SealedBlock readSealedBlock(Object? block, Map config) {
  _need(block is Map<String, dynamic>, 'the sealed block must be an object');
  block as Map<String, dynamic>;
  _need(block['v'] == sealedVersion, 'sealed v must be 1');
  final scope = block['scope'];
  _need(
    scope is Map && _sameScope(scope, config['scope'] as Map),
    "the sealed scope must be the page's scope",
  );
  _need(
      _isUuid(block['rootFolderId']), 'rootFolderId must be a lowercase UUID');

  final c = block['catalog'];
  _need(c is Map, 'catalog must be an object');
  c as Map;
  _need(_isPlainPath(c['path']), 'catalog.path must be a plain relative path');
  _need(_isTxId(c['txId']), 'catalog.txId must be a transaction ID');
  final catalogKey = fromB64u(c['key'], bytes: keyBytes, what: 'catalog.key');
  final tags = c['tags'];
  _need(tags is Map && tags.values.every((v) => v is String),
      'catalog.tags values are strings');
  tags as Map;
  _need(tags['Cipher'] == sealCipher, 'catalog.tags.Cipher must be AES256-GCM');
  fromB64u(tags['Cipher-IV'], bytes: ivBytes, what: 'catalog Cipher-IV');

  final files = block['files'];
  _need(files is Map, 'files must be an object');
  final fileKeys = <String, Uint8List>{};
  for (final MapEntry(:key, :value) in (files as Map).entries) {
    _need(_isUuid(key), 'a files key must be a lowercase UUID');
    fileKeys[key as String] =
        fromB64u(value, bytes: keyBytes, what: 'the key of $key');
  }

  final ciphers = block['ciphers'];
  _need(ciphers is Map, 'ciphers must be an object');
  final dataCiphers = <String, SealedCipher>{};
  for (final MapEntry(:key, :value) in (ciphers as Map).entries) {
    _need(_isTxId(key), 'a ciphers key must be a transaction ID');
    _need(value is Map && value['cipher'] is String,
        'ciphers.$key needs a cipher');
    final cipher = (value as Map)['cipher'] as String;
    final iv = value['iv'];
    if (knownDataCiphers.contains(cipher)) {
      _need(iv is String && iv.isNotEmpty, 'ciphers.$key needs an iv');
      fromB64u(iv, what: 'ciphers.$key.iv');
    }
    dataCiphers[key as String] =
        SealedCipher(cipher: cipher, iv: iv is String ? iv : null);
  }

  return SealedBlock(
    json: block,
    rootFolderId: block['rootFolderId'] as String,
    catalog: SealedCatalog(
      path: c['path'] as String,
      txId: c['txId'] as String,
      key: catalogKey,
      tags: tags.cast<String, String>(),
    ),
    files: fileKeys,
    ciphers: dataCiphers,
  );
}

final _keyShaped = RegExp(r'^[A-Za-z0-9_-]{43}$');

/// Whether typed text could be a pasted publication key: 43 base64url
/// characters.
bool looksLikeKey(String text) => _keyShaped.hasMatch(text);

/// The key [text] spells, or null: a non-canonical spelling is not a key,
/// and may be a password.
Uint8List? keyFrom(String? text) {
  if (text == null || !looksLikeKey(text)) return null;
  try {
    return fromB64u(text, bytes: keyBytes, what: 'a key');
  } on SealError {
    return null;
  }
}
