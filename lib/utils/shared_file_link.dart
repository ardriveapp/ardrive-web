import 'dart:typed_data';

import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/validate_arweave_id.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:arweave/utils.dart' as arweave_utils;
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:equatable/equatable.dart';

// The v2 shared file link schema - see `docs/FILE_SHARING_REDESIGN_PLAN.md`
// §1.2 for the normative field table and §1.3 for example links.
//
// The schema is transport independent by design. Phase 1 ships it on the hash
// route (`/#/file/{fileId}/view?v=2&...`); Phase 3 puts the same parameters on
// `/share/{fileId}?v=2&...`. Nothing here knows about either route apart from
// [SharedFileLinkRoute] and `buildSharedFileLinkLocation`, which know both
// shapes but not which one is live - that is the URL strategy's business
// (`lib/utils/app_url_strategy.dart`).
//
// Three rules hold everywhere in this file:
//
// 1. Nothing throws. Every field is parsed defensively; a malformed field is
//    dropped on its own and logged, and the rest of the link still parses. A
//    link that arrives mangled must never take the router down with it.
// 2. Absence is representable. A `null` field means "the link did not carry
//    this" - the caller then applies the "Absent ⇒ client behavior" column of
//    §1.2. It never means "the link said nothing sensible".
// 3. Nothing secret is logged. The key is never logged, and neither are the
//    values of `n`/`ct`, which are private file secrets when embedded.

/// Parameter names for the shared file link schema.
///
/// Single source of truth: link builders, the route parser and any UI that
/// inspects a link must take names from here. A parameter name spelled out
/// twice is a parameter name that will drift.
class SharedFileLinkParams {
  const SharedFileLinkParams._();

  /// Schema version. Only [SharedFileLinkPayload.currentVersion] selects the
  /// payload fast path; anything else is a v1 link.
  static const version = 'v';

  /// Data transaction (or data item) id of the shared revision.
  static const dataTxId = 'dtx';

  /// Metadata transaction id of the shared revision.
  static const metadataTxId = 'mtx';

  /// Owner address of the file.
  static const owner = 'own';

  /// File name. Sensitive for private files - omitted when the sharer hides
  /// the file's details.
  static const name = 'n';

  /// File size in bytes.
  static const size = 's';

  /// Content type. Sensitive for private files, same toggle as [name].
  static const contentType = 'ct';

  /// Cipher name, one of [Cipher.aes256gcm] / [Cipher.aes256ctr].
  static const cipher = 'c';

  /// Cipher IV, base64url encoded, 12 bytes.
  static const cipherIv = 'iv';

  /// `1` when the link is pinned to the shared revision.
  static const pinned = 'pin';

  /// Id of the bundle the data item was posted in. Diagnostic only.
  static const bundledIn = 'in';

  /// Transaction id of the file's thumbnail.
  static const thumbnailTxId = 'thn';

  /// `1` when the sharer hid the file's name and size.
  static const hidden = 'hid';

  /// The file key.
  ///
  /// Read from the `#k=` fragment when there is one, and from the hash
  /// route's pseudo query otherwise (see [SharedFileLinkKeySource]).
  static const key = 'k';

  /// The v1 key parameter. Honored forever - permanent links in the wild must
  /// never break.
  static const legacyKey = 'fileKey';

  /// The value every boolean flag in this schema uses.
  static const flagTrue = '1';

  /// Every parameter name this schema understands.
  ///
  /// Unknown parameters are ignored, never rejected; this set exists so that
  /// builders can assert they are not inventing names.
  static const all = <String>{
    version,
    dataTxId,
    metadataTxId,
    owner,
    name,
    size,
    contentType,
    cipher,
    cipherIv,
    pinned,
    bundledIn,
    thumbnailTxId,
    hidden,
    key,
    legacyKey,
  };
}

/// Where the file key in a link came from.
///
/// Declaration order after [none] is precedence order, highest first, and the
/// resolver relies on it. See `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.2.
enum SharedFileLinkKeySource {
  /// No key travelled in the link.
  none,

  /// A real `#k=` fragment.
  ///
  /// This is the Phase 3 position. It is already readable today: with hash
  /// routing the router's location is everything after the first `#`, so a
  /// nested `...?v=2#k=...` still exposes the key through `Uri.fragment`.
  fragment,

  /// The `k` parameter of the (pseudo) query.
  ///
  /// This is where Phase 1 writes the key. On the hash route the query lives
  /// after the `#`, so it is never sent to a server - which is the property
  /// the fragment buys us in Phase 3, available today.
  query,

  /// The v1 `fileKey` parameter. Honored forever.
  legacyQuery,
}

/// The route shape a shared file link is written on.
///
/// Both shapes are parsed forever and under either URL strategy - see
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §1.1 and §4.1. This only says which
/// one a *newly built* link uses, which follows the active URL strategy
/// (`AppUrlStrategy.sharedFileRoute`).
enum SharedFileLinkRoute {
  /// `/file/{fileId}/view` - the shape of every link ArDrive has produced, and
  /// the shape the hash route keeps using.
  legacy,

  /// `/share/{fileId}` - the canonical route of §1.1, reachable only once the
  /// host answers it with `index.html`.
  share;

  /// The first path segment of [legacy].
  static const legacySegment = 'file';

  /// The last path segment of [legacy].
  static const legacyViewSegment = 'view';

  /// The first path segment of [share].
  static const shareSegment = 'share';

  /// The route location this shape gives [fileId].
  String pathFor(String fileId) => this == SharedFileLinkRoute.share
      ? '/$shareSegment/$fileId'
      : '/$legacySegment/$fileId/$legacyViewSegment';
}

/// Where a link builder should put the file key.
enum SharedFileLinkKeyPlacement {
  /// In the query - only legal for a URL whose query sits after the `#`, which
  /// is every link Phase 1 produces. Never use this once the app moves to path
  /// routing: a path-route query is sent to the server.
  hashQuery,

  /// In a `#k=` fragment. Correct under path routing (Phase 3), and also valid
  /// today as a nested fragment.
  fragment,
}

/// The file key carried by a shared file link, and where it came from.
///
/// A key that is present but unusable is *not* the same as no key at all: the
/// recipient was sent a key and would otherwise be left wondering why it is
/// being ignored. [isDamaged] carries that distinction through to the UI so it
/// can show the locked state with an inline "this link is damaged" error
/// rather than a bare key prompt.
class SharedFileLinkKey extends Equatable {
  /// The key exactly as it appeared in the link, once validated.
  ///
  /// `null` when the link carried no key, or carried one that is damaged.
  final String? raw;

  /// The decoded 32 key bytes, or `null` when there is no usable key.
  ///
  /// Deliberately excluded from [props]: it is derived from [raw].
  final Uint8List? bytes;

  /// Where [raw] came from, or [SharedFileLinkKeySource.none].
  ///
  /// Set even when the key is damaged, so diagnostics can name the source.
  final SharedFileLinkKeySource source;

  /// Whether the link carried a key that could not be used.
  ///
  /// Links get truncated and mangled in transit all the time.
  final bool isDamaged;

  const SharedFileLinkKey._({
    this.raw,
    this.bytes,
    this.source = SharedFileLinkKeySource.none,
    this.isDamaged = false,
  });

  /// A file key of 32 bytes, base64url encoded and unpadded.
  static const length = 43;

  /// The number of bytes a file key decodes to.
  static const lengthInBytes = 32;

  /// No key travelled in the link, and nothing was damaged.
  static const absent = SharedFileLinkKey._();

  /// A key travelled in the link but could not be used.
  factory SharedFileLinkKey.damaged(SharedFileLinkKeySource source) =>
      SharedFileLinkKey._(source: source, isDamaged: true);

  /// Validates [value] and returns the key it encodes.
  ///
  /// Returns [absent] for an empty value - an empty parameter is an absent
  /// key, not a mangled one - and a [damaged] key for anything that fails
  /// validation. Never throws.
  factory SharedFileLinkKey.parse(
    String? value, {
    required SharedFileLinkKeySource source,
  }) {
    if (value == null || value.isEmpty) {
      return absent;
    }

    if (!isWellFormed(value)) {
      logger.e(
        'Dropped the file key in the shared file link: it is not a well '
        'formed $length character base64url key (source: ${source.name})',
      );

      return SharedFileLinkKey.damaged(source);
    }

    try {
      final bytes = arweave_utils.decodeBase64ToBytes(value);

      if (bytes.length != lengthInBytes) {
        logger.e(
          'Dropped the file key in the shared file link: it decoded to '
          '${bytes.length} bytes instead of $lengthInBytes '
          '(source: ${source.name})',
        );

        return SharedFileLinkKey.damaged(source);
      }

      return SharedFileLinkKey._(raw: value, bytes: bytes, source: source);
    } catch (e) {
      // Unreachable for anything [isWellFormed] accepts, but a decoder is not
      // something to take on trust while parsing a route.
      //
      // The reason only, like every other branch here: the `source` of the
      // `FormatException` a base64 decoder throws is the key it was given, and
      // `toString()` prints a window of it (rule 3).
      logger.e(
        'Failed to decode the file key in the shared file link: '
        '${e is FormatException ? e.message : e.runtimeType} '
        '(source: ${source.name})',
      );

      return SharedFileLinkKey.damaged(source);
    }
  }

  /// Resolves the key of [uri] across every source, honoring the precedence of
  /// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.2.
  ///
  /// Works for v1 and v2 links alike, so the key of a link is resolved by one
  /// code path no matter which schema the link uses.
  factory SharedFileLinkKey.resolve(Uri uri) {
    Map<String, String> queryParameters = const {};
    Map<String, String> fragmentParameters = const {};

    try {
      queryParameters = uri.queryParameters;
    } on FormatException catch (e) {
      // The route parser guards this too; a bad escape must not throw here
      // either, since this is also called from link inspection code.
      //
      // Only the reason is logged: this exception's `source` is the query
      // being resolved *for its key*, so it is the one string in the app that
      // must never reach the log (rule 3).
      logger.e('Failed to read the query of a shared file link: ${e.message}');
    }

    try {
      final fragment = uri.fragment;

      if (fragment.isNotEmpty) {
        fragmentParameters = Uri.splitQueryString(fragment);
      }
    } on FormatException catch (e) {
      // `#k=<key>` is the fragment being split here, so the exception's
      // `source` is a key. The reason travels; the value never does.
      logger.e(
        'Failed to read the fragment of a shared file link: ${e.message}',
      );
    }

    return SharedFileLinkKey.resolveFromParameters(
      queryParameters,
      fragmentParameters: fragmentParameters,
    );
  }

  /// Resolves the key from already-split parameters.
  ///
  /// Precedence, highest first: `#k=` fragment, `k` query parameter, legacy
  /// `fileKey` query parameter, none. The highest *present* source wins even
  /// when it is damaged - a lower source is never silently substituted, and
  /// two keys are never surfaced at once.
  factory SharedFileLinkKey.resolveFromParameters(
    Map<String, String> queryParameters, {
    Map<String, String> fragmentParameters = const {},
  }) {
    final candidates = <SharedFileLinkKeySource, String>{};

    void consider(SharedFileLinkKeySource source, String? value) {
      // An empty parameter is an absent key, not a mangled one.
      if (value != null && value.isNotEmpty) {
        candidates[source] = value;
      }
    }

    consider(
      SharedFileLinkKeySource.fragment,
      fragmentParameters[SharedFileLinkParams.key],
    );
    consider(
      SharedFileLinkKeySource.query,
      queryParameters[SharedFileLinkParams.key],
    );
    consider(
      SharedFileLinkKeySource.legacyQuery,
      queryParameters[SharedFileLinkParams.legacyKey],
    );

    if (candidates.isEmpty) {
      return absent;
    }

    // Enum declaration order is precedence order.
    final winner = candidates.keys.reduce(
      (a, b) => a.index <= b.index ? a : b,
    );

    if (candidates.length > 1) {
      final disagree = candidates.values.toSet().length > 1;

      logger.w(
        'The shared file link carries ${candidates.length} key sources '
        '(${candidates.keys.map((s) => s.name).join(', ')}) that '
        '${disagree ? 'disagree' : 'agree'}. Using ${winner.name}.',
      );
    }

    return SharedFileLinkKey.parse(candidates[winner], source: winner);
  }

  /// Whether [value] has the shape of a file key.
  ///
  /// Checked before any crypto so that a truncated paste is answered instantly
  /// instead of through a decrypt round trip. A 32-byte key is 43 base64url
  /// characters, and the last character carries only 4 significant bits, so
  /// its low 2 bits must be zero - otherwise Dart's strict decoder throws
  /// `Invalid encoding before padding`. `Q` (alphabet index 16) is a valid
  /// final character; `q` (index 42) is not.
  static bool isWellFormed(String value) {
    if (value.length != length || !_base64UrlPattern.hasMatch(value)) {
      return false;
    }

    final lastCharacterIndex = _base64UrlAlphabet.indexOf(value[length - 1]);

    return lastCharacterIndex >= 0 && lastCharacterIndex % 4 == 0;
  }

  /// Whether there is a key that can actually be used to decrypt.
  bool get isUsable => bytes != null;

  /// The key as a [SecretKey], or `null` when there is no usable key.
  SecretKey? get secretKey {
    final bytes = this.bytes;

    return bytes == null ? null : SecretKey(bytes);
  }

  /// The `#k=...` fragment for this key, or `null` when there is none to
  /// write.
  String? get fragment =>
      raw == null ? null : '${SharedFileLinkParams.key}=$raw';

  @override
  List<Object?> get props => [raw, source, isDamaged];

  // Never let key material reach a log line or a widget inspector.
  @override
  String toString() => 'SharedFileLinkKey(source: ${source.name}, '
      'isDamaged: $isDamaged, key: ${raw == null ? 'none' : '<redacted>'})';

  static final _base64UrlPattern = RegExp('^[A-Za-z0-9_-]{$length}\$');
  static const _base64UrlAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
}

/// Everything a v2 shared file link carries, parsed.
///
/// A payload exists only for a link that declares `v=2`. A link without it -
/// every link ArDrive has ever produced until now - parses to `null`, and the
/// recipient falls back to resolving the file over GraphQL exactly as it does
/// today.
///
/// Every field is independently optional: a link with nothing but `v=2` is
/// valid, and so is one that lost half its parameters to a chat client. The
/// "Absent ⇒ client behavior" column of §1.2 is the contract for what a `null`
/// means to the UI.
class SharedFileLinkPayload extends Equatable {
  /// The only schema version that has a payload.
  static const currentVersion = 2;

  /// §1.2: filenames are truncated to this length by the builder, and a longer
  /// one in a parsed link is dropped rather than trusted.
  static const maxNameLength = 120;

  /// Generous, but bounded: a content type is `type/subtype`, not an essay.
  static const maxContentTypeLength = 255;

  /// Both ciphers use a 12-byte IV (`_aesNonceLengthBytes` in
  /// `packages/ardrive_crypto/lib/src/stream_aes.dart`).
  static const cipherIvLengthInBytes = 12;

  /// Cipher names this schema accepts for `c`.
  static const supportedCiphers = <String>{
    Cipher.aes256gcm,
    Cipher.aes256ctr,
  };

  /// The schema version the link declared. Always [currentVersion] today.
  final int version;

  /// `dtx` - data transaction id of the shared revision.
  ///
  /// Absent ⇒ resolve it over GraphQL before any fetch.
  final String? dataTxId;

  /// `mtx` - metadata transaction id of the shared revision.
  ///
  /// Absent ⇒ no background verification of the link's claims.
  final String? metadataTxId;

  /// `own` - the file owner's address.
  ///
  /// Absent ⇒ resolve the owner from `mtx`, else from a first-writer probe.
  final String? ownerAddress;

  /// `n` - the file name.
  ///
  /// Absent ⇒ the header shows a generic title until metadata resolves or
  /// decrypts. Also absent whenever [detailsAreHidden] is set.
  final String? name;

  /// `s` - the file size in bytes.
  ///
  /// Absent ⇒ no size chip, and download progress is indeterminate until the
  /// gateway reports a content length.
  final int? size;

  /// `ct` - the content type.
  ///
  /// Absent ⇒ infer from [name], else treat as `application/octet-stream`.
  final String? contentType;

  /// `c` - the cipher, one of [supportedCiphers].
  ///
  /// Present ⇒ the file is private. Absent ⇒ one `getTransactionDetails` GQL
  /// at download or preview time, as today. Absent does *not* mean public.
  final String? cipher;

  /// `iv` - the cipher IV, base64url encoded.
  ///
  /// Absent ⇒ the same GQL fallback as [cipher].
  final String? cipherIv;

  /// `pin` - whether the link is pinned to the revision it was made from.
  ///
  /// `false` (absent) is live semantics: the freshness check offers a newer
  /// revision. `true` keeps the download target fixed and only says a newer
  /// revision exists.
  final bool isPinned;

  /// `in` - the bundle the data item was posted in. Diagnostic only.
  final String? bundledInTxId;

  /// `thn` - transaction id of the file's thumbnail.
  ///
  /// Absent ⇒ a type icon instead of a thumbnail image.
  final String? thumbnailTxId;

  /// `hid` - whether the sharer hid the file's name and size.
  ///
  /// `false` (absent) ⇒ the details were embedded, or the link is legacy.
  /// Presence only tunes the locked page's copy.
  final bool detailsAreHidden;

  /// The file key the link carried, from any source. Never `null`; use
  /// [SharedFileLinkKey.absent] semantics ([SharedFileLinkKey.isUsable] /
  /// [SharedFileLinkKey.isDamaged]) to tell the cases apart.
  final SharedFileLinkKey key;

  const SharedFileLinkPayload({
    this.version = currentVersion,
    this.dataTxId,
    this.metadataTxId,
    this.ownerAddress,
    this.name,
    this.size,
    this.contentType,
    this.cipher,
    this.cipherIv,
    this.isPinned = false,
    this.bundledInTxId,
    this.thumbnailTxId,
    this.detailsAreHidden = false,
    this.key = SharedFileLinkKey.absent,
  });

  /// Parses the payload of [uri], or returns `null` when [uri] is not a v2
  /// link.
  ///
  /// Pass [key] when the key has already been resolved for the same link, so
  /// that it is resolved exactly once.
  static SharedFileLinkPayload? tryParse(Uri uri, {SharedFileLinkKey? key}) {
    Map<String, String> queryParameters;

    try {
      queryParameters = uri.queryParameters;
    } on FormatException catch (e) {
      // The reason only: the `source` of this exception is the query of a
      // shared file link, which is where a v1 link carries its key (rule 3).
      logger.e('Failed to read the query of a shared file link: ${e.message}');

      return null;
    }

    return tryParseParameters(
      queryParameters,
      key: key ?? SharedFileLinkKey.resolve(uri),
    );
  }

  /// Parses the payload from already-split query parameters, or returns `null`
  /// when they do not declare `v=[currentVersion]`.
  ///
  /// Unknown parameters are ignored. Every known one that fails validation is
  /// dropped on its own, logged, and leaves the rest of the payload intact.
  static SharedFileLinkPayload? tryParseParameters(
    Map<String, String> parameters, {
    SharedFileLinkKey? key,
  }) {
    final rawVersion = parameters[SharedFileLinkParams.version];

    if (rawVersion == null || rawVersion.isEmpty) {
      // A link without a version is a v1 link: today's GQL resolution path.
      return null;
    }

    final version = int.tryParse(rawVersion);

    if (version == null || version != currentVersion) {
      // Either junk, or a schema from a future release this build cannot read.
      // Both degrade to the v1 path, which resolves everything over GraphQL
      // and therefore cannot be wrong about anything the link asserted.
      logger.w(
        'Ignoring the payload of a shared file link: unsupported schema '
        'version. Falling back to GraphQL resolution.',
      );

      return null;
    }

    return SharedFileLinkPayload(
      version: version,
      dataTxId: _arweaveId(parameters, SharedFileLinkParams.dataTxId),
      metadataTxId: _arweaveId(parameters, SharedFileLinkParams.metadataTxId),
      ownerAddress: _arweaveId(parameters, SharedFileLinkParams.owner),
      name: _name(parameters),
      size: _size(parameters),
      contentType: _contentType(parameters),
      cipher: _cipher(parameters),
      cipherIv: _cipherIv(parameters),
      isPinned: _flag(parameters, SharedFileLinkParams.pinned),
      bundledInTxId: _arweaveId(parameters, SharedFileLinkParams.bundledIn),
      thumbnailTxId: _arweaveId(parameters, SharedFileLinkParams.thumbnailTxId),
      detailsAreHidden: _flag(parameters, SharedFileLinkParams.hidden),
      key: key ?? SharedFileLinkKey.resolveFromParameters(parameters),
    );
  }

  /// The query parameters for this payload, in the canonical order of §1.3.
  ///
  /// Fields that are absent are omitted entirely - the schema has no empty
  /// values. Values are returned undecoded; percent-encoding is the URL
  /// builder's job (see [buildSharedFileLinkLocation]).
  ///
  /// [includeKey] writes the key as `k`. It is only ever legal for a URL whose
  /// query is not sent to a server - which today means the hash route, and
  /// after Phase 3 means nothing at all. Default off, and off is what the
  /// share dialog uses unless the sharer opts in.
  Map<String, String> toQueryParameters({bool includeKey = false}) {
    final parameters = <String, String>{
      SharedFileLinkParams.version: '$version',
    };

    void put(String name, String? value) {
      if (value != null && value.isNotEmpty) {
        parameters[name] = value;
      }
    }

    if (isPinned) {
      parameters[SharedFileLinkParams.pinned] = SharedFileLinkParams.flagTrue;
    }

    if (detailsAreHidden) {
      parameters[SharedFileLinkParams.hidden] = SharedFileLinkParams.flagTrue;
    }

    put(SharedFileLinkParams.dataTxId, dataTxId);
    put(SharedFileLinkParams.metadataTxId, metadataTxId);
    put(SharedFileLinkParams.owner, ownerAddress);
    put(SharedFileLinkParams.name, name);
    put(SharedFileLinkParams.size, size?.toString());
    put(SharedFileLinkParams.contentType, contentType);
    put(SharedFileLinkParams.cipher, cipher);
    put(SharedFileLinkParams.cipherIv, cipherIv);
    put(SharedFileLinkParams.bundledIn, bundledInTxId);
    put(SharedFileLinkParams.thumbnailTxId, thumbnailTxId);

    if (includeKey) {
      put(SharedFileLinkParams.key, key.raw);
    }

    return parameters;
  }

  /// Whether the link can be resolved without a GraphQL round trip.
  bool get hasFastPathTarget => dataTxId != null;

  /// Whether the link carries everything needed to decrypt without asking the
  /// gateway for the file's tags.
  bool get hasCipherDetails => cipher != null && cipherIv != null;

  SharedFileLinkPayload copyWith({
    int? version,
    String? dataTxId,
    String? metadataTxId,
    String? ownerAddress,
    String? name,
    int? size,
    String? contentType,
    String? cipher,
    String? cipherIv,
    bool? isPinned,
    String? bundledInTxId,
    String? thumbnailTxId,
    bool? detailsAreHidden,
    SharedFileLinkKey? key,
  }) =>
      SharedFileLinkPayload(
        version: version ?? this.version,
        dataTxId: dataTxId ?? this.dataTxId,
        metadataTxId: metadataTxId ?? this.metadataTxId,
        ownerAddress: ownerAddress ?? this.ownerAddress,
        name: name ?? this.name,
        size: size ?? this.size,
        contentType: contentType ?? this.contentType,
        cipher: cipher ?? this.cipher,
        cipherIv: cipherIv ?? this.cipherIv,
        isPinned: isPinned ?? this.isPinned,
        bundledInTxId: bundledInTxId ?? this.bundledInTxId,
        thumbnailTxId: thumbnailTxId ?? this.thumbnailTxId,
        detailsAreHidden: detailsAreHidden ?? this.detailsAreHidden,
        key: key ?? this.key,
      );

  @override
  List<Object?> get props => [
        version,
        dataTxId,
        metadataTxId,
        ownerAddress,
        name,
        size,
        contentType,
        cipher,
        cipherIv,
        isPinned,
        bundledInTxId,
        thumbnailTxId,
        detailsAreHidden,
        key,
      ];

  // `n` and `ct` are private file secrets when they are embedded, so they are
  // named but never printed.
  @override
  String toString() => 'SharedFileLinkPayload(v: $version, '
      'dtx: $dataTxId, mtx: $metadataTxId, own: $ownerAddress, '
      'n: ${name == null ? 'absent' : '<omitted>'}, s: $size, '
      'ct: ${contentType == null ? 'absent' : '<omitted>'}, '
      'c: $cipher, iv: $cipherIv, pin: $isPinned, in: $bundledInTxId, '
      'thn: $thumbnailTxId, hid: $detailsAreHidden, key: $key)';

  /// Transaction ids and owner addresses share one shape: 43 base64url
  /// characters.
  static String? _arweaveId(Map<String, String> parameters, String name) {
    final value = parameters[name];

    if (value == null || value.isEmpty) {
      return null;
    }

    if (!isArweaveTransactionID(value)) {
      logger.w(
        'Dropped `$name` from a shared file link: not a 43 character '
        'base64url id.',
      );

      return null;
    }

    return value;
  }

  static String? _name(Map<String, String> parameters) =>
      sanitizeName(parameters[SharedFileLinkParams.name]);

  /// Validates a file name hint, returning `null` when it is absent or must be
  /// dropped.
  ///
  /// Public because `/view/{txId}` carries the same `n` hint under the same
  /// rules (§1.3) - one validator, not two that drift apart.
  static String? sanitizeName(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.length > maxNameLength) {
      logger.w(
        'Dropped `${SharedFileLinkParams.name}` from a shared file link: '
        '${value.length} characters exceeds the $maxNameLength character '
        'limit.',
      );

      return null;
    }

    if (unsafeNameCharacterPattern.hasMatch(value)) {
      logger.w(
        'Dropped `${SharedFileLinkParams.name}` from a shared file link: it '
        'contains control or direction characters.',
      );

      return null;
    }

    return value;
  }

  static int? _size(Map<String, String> parameters) {
    final value = parameters[SharedFileLinkParams.size];

    if (value == null || value.isEmpty) {
      return null;
    }

    final size = int.tryParse(value);

    if (size == null || size < 0) {
      logger.w(
        'Dropped `${SharedFileLinkParams.size}` from a shared file link: not '
        'a non-negative integer.',
      );

      return null;
    }

    return size;
  }

  static String? _contentType(Map<String, String> parameters) =>
      sanitizeContentType(parameters[SharedFileLinkParams.contentType]);

  /// Validates a content type hint, returning `null` when it is absent or must
  /// be dropped. Shared with `/view/{txId}`'s `ct` hint, as [sanitizeName] is.
  ///
  /// [_contentTypePattern] is anchored and lists the characters a MIME type may
  /// contain, so nothing in [unsafeNameCharacterPattern] can survive it - a
  /// `ct` carrying a direction override is already dropped as "not a
  /// `type/subtype`".
  static String? sanitizeContentType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (value.length > maxContentTypeLength ||
        !_contentTypePattern.hasMatch(value)) {
      logger.w(
        'Dropped `${SharedFileLinkParams.contentType}` from a shared file '
        'link: not a `type/subtype` MIME type.',
      );

      return null;
    }

    return value;
  }

  static String? _cipher(Map<String, String> parameters) {
    final value = parameters[SharedFileLinkParams.cipher];

    if (value == null || value.isEmpty) {
      return null;
    }

    if (!supportedCiphers.contains(value)) {
      // Falls back to reading the cipher tag off the transaction, which is
      // authoritative anyway.
      logger.w(
        'Dropped `${SharedFileLinkParams.cipher}` from a shared file link: '
        'unknown cipher.',
      );

      return null;
    }

    return value;
  }

  static String? _cipherIv(Map<String, String> parameters) {
    final value = parameters[SharedFileLinkParams.cipherIv];

    if (value == null || value.isEmpty) {
      return null;
    }

    try {
      final bytes = arweave_utils.decodeBase64ToBytes(value);

      if (bytes.length != cipherIvLengthInBytes) {
        logger.w(
          'Dropped `${SharedFileLinkParams.cipherIv}` from a shared file '
          'link: ${bytes.length} bytes instead of $cipherIvLengthInBytes.',
        );

        return null;
      }
    } catch (e) {
      logger.w(
        'Dropped `${SharedFileLinkParams.cipherIv}` from a shared file link: '
        'not valid base64. Error: $e',
      );

      return null;
    }

    return value;
  }

  static bool _flag(Map<String, String> parameters, String name) {
    final value = parameters[name];

    if (value == null || value.isEmpty) {
      return false;
    }

    if (value == SharedFileLinkParams.flagTrue) {
      return true;
    }

    if (value != '0') {
      logger.w(
        'Ignored `$name` in a shared file link: expected '
        '`${SharedFileLinkParams.flagTrue}`.',
      );
    }

    return false;
  }

  static final _contentTypePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*/[A-Za-z0-9][A-Za-z0-9!#$&^_.+-]*$',
  );

  /// Characters a file name may never carry, whether it came out of a link or
  /// off a transaction tag.
  ///
  /// Two classes, one rule. The C0 range and DEL are the classic way to make a
  /// string print as something other than what it is. The rest are Unicode's
  /// direction controls - the overrides `U+202A`-`U+202E`, the isolates
  /// `U+2066`-`U+2069` and the marks `U+200E`/`U+200F` - and they matter here
  /// because `n` is not only rendered: it is the name the file is *saved*
  /// under. `Q3-Report<U+202E>fdp.exe` reads as `Q3-Reportexe.pdf` in the card
  /// and in the operating system's save dialog, and lands on disk as an
  /// executable.
  ///
  /// A name carrying one is dropped whole rather than repaired, which is the
  /// rule every other malformed field in this file follows: the caller then
  /// falls back to the name the file's own record gives, and a sender who
  /// wanted a name shown has to send one that says what it is.
  static final unsafeNameCharacterPattern = RegExp(
    r'[\x00-\x1f\x7f\u200e\u200f\u202a-\u202e\u2066-\u2069]',
  );
}

/// The route location of a shared file link - what
/// `AppRouteInformationParser.restoreRouteInformation` returns, and what a link
/// builder appends to an origin (after `/#` on the hash route, directly on a
/// path route).
///
/// Pass a [payload] to build a v2 link and omit it to build a v1 link, which
/// keeps the exact shape ArDrive has always produced.
///
/// [route] picks the route shape; it follows the active URL strategy, and the
/// default is the shape every link has always used.
///
/// The key is written into the position [keyPlacement] names, and only when
/// there is one to write. On the hash route both positions live after the `#`,
/// so the key is never sent to a server either way; on a path route only
/// [SharedFileLinkKeyPlacement.fragment] is safe.
String buildSharedFileLinkLocation({
  required String fileId,
  SharedFileLinkPayload? payload,
  String? rawFileKey,
  SharedFileLinkKeyPlacement keyPlacement =
      SharedFileLinkKeyPlacement.hashQuery,
  SharedFileLinkRoute route = SharedFileLinkRoute.legacy,
}) {
  final path = route.pathFor(fileId);
  final candidateKey = rawFileKey ?? payload?.key.raw;
  final key =
      candidateKey == null || candidateKey.isEmpty ? null : candidateKey;

  if (payload == null) {
    // v1: nothing but the key travels at all. In the query it keeps the
    // `fileKey` name every link ever generated used; in a fragment it becomes
    // `k`, which is the only name that position has ever had.
    if (key == null) {
      return path;
    }

    return keyPlacement == SharedFileLinkKeyPlacement.fragment
        ? '$path#${SharedFileLinkParams.key}=${_encode(key)}'
        : '$path?${SharedFileLinkParams.legacyKey}=${_encode(key)}';
  }

  final parameters = payload.toQueryParameters();
  var fragment = '';

  if (key != null) {
    if (keyPlacement == SharedFileLinkKeyPlacement.hashQuery) {
      parameters[SharedFileLinkParams.key] = key;
    } else {
      fragment = '#${SharedFileLinkParams.key}=${_encode(key)}';
    }
  }

  final query = parameters.entries
      .map((entry) => '${entry.key}=${_encode(entry.value)}')
      .join('&');

  return '$path?$query$fragment';
}

/// Percent-encodes a parameter value.
///
/// [Uri.encodeComponent] rather than [Uri.encodeQueryComponent] so that a
/// space becomes `%20` and not `+`: the schema's examples use `%20`, and `+`
/// only decodes back to a space in readers that know it is a query.
String _encode(String value) => Uri.encodeComponent(value);
