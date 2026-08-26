import 'dart:convert';
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
// A v2 link carries everything it asserts in one packed parameter, `d`, and
// the file key in `k` (or `#k=`) beside it. The byte layout is documented on
// [SharedFileLinkPayload.encode]; nothing outside this file needs to know it.
//
// The schema is transport independent by design. Phase 1 ships it on the hash
// route (`/#/file/{fileId}/view?d=...`); Phase 3 puts the same parameter on
// `/share/{fileId}?d=...`. Nothing here knows about either route apart from
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

/// The alphabet [base64Url] encodes with, in index order.
const _base64UrlAlphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

/// Whether [value] is the canonical 43 character base64url spelling of 32
/// bytes - the shape of every Arweave transaction id, every owner address and
/// every ArFS file key.
///
/// [isArweaveTransactionID] answers half of that: 43 characters drawn from the
/// base64url alphabet. The other half is what a strict decoder demands. 43
/// characters carry 258 bits and 32 bytes are 256 of them, so the final
/// character's low 2 bits must be zero - `Q` (alphabet index 16) qualifies,
/// `q` (index 42) does not, and a decoder handed `q` throws `Invalid encoding
/// before padding` rather than returning something short.
///
/// This matters more than it used to: a v2 payload stores ids as the 32 bytes
/// they are, so an id that will not decode is an id that cannot travel at all.
bool isCanonical32ByteId(String value) {
  if (!isArweaveTransactionID(value)) {
    return false;
  }

  final lastCharacterIndex =
      _base64UrlAlphabet.indexOf(value[value.length - 1]);

  return lastCharacterIndex >= 0 && lastCharacterIndex % 4 == 0;
}

/// Parameter names for the shared file link schema, and the names of the fields
/// its payload carries.
///
/// Single source of truth: link builders, the route parser and any UI that
/// inspects a link must take names from here. A parameter name spelled out
/// twice is a parameter name that will drift.
class SharedFileLinkParams {
  const SharedFileLinkParams._();

  // ---------------------------------------------------------------------------
  // Parameter names - what actually appears in a link
  // ---------------------------------------------------------------------------

  /// The packed v2 payload, base64url encoded (see
  /// [SharedFileLinkPayload.encode]).
  ///
  /// Its presence is what makes a link a v2 link. The schema version lives in
  /// the payload's first byte rather than in a parameter of its own, so there
  /// is exactly one thing to look at and one thing to get wrong.
  static const payload = 'd';

  /// The file key.
  ///
  /// Read from the `#k=` fragment when there is one, and from the hash
  /// route's pseudo query otherwise (see [SharedFileLinkKeySource]).
  static const key = 'k';

  /// The v1 key parameter. Honored forever - permanent links in the wild must
  /// never break.
  static const legacyKey = 'fileKey';

  // ---------------------------------------------------------------------------
  // Field names - what the payload carries, and what a diagnostic calls it
  // ---------------------------------------------------------------------------
  //
  // These are the schema's vocabulary, not its wire format: the payload is
  // packed, so none of them appears in a URL. They are what §1.2's field table
  // calls each field, what a log line names when a field is dropped, and what
  // `SharedFileCubit` lists when a link disagrees with the file's own record.
  //
  // [name] and [contentType] are the exception: they *are* parameter names on
  // `/view/{txId}`, which carries the same two hints under the same validation
  // (`lib/utils/raw_transaction_link.dart`).

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

  /// Cipher IV, 12 bytes.
  static const cipherIv = 'iv';

  /// Whether the link is pinned to the shared revision.
  static const pinned = 'pin';

  /// Id of the bundle the data item was posted in. Diagnostic only.
  static const bundledIn = 'in';

  /// Transaction id of the file's thumbnail.
  static const thumbnailTxId = 'thn';

  /// Whether the sharer hid the file's name and size.
  static const hidden = 'hid';

  /// Every parameter name a link may carry.
  ///
  /// Unknown parameters are ignored, never rejected; this set exists so that
  /// builders can assert they are not inventing names.
  static const all = <String>{
    payload,
    key,
    legacyKey,
    name,
    contentType,
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
  /// instead of through a decrypt round trip. A file key is 32 bytes, which is
  /// exactly the shape [isCanonical32ByteId] describes - the same check every
  /// transaction id and owner address in a link goes through, and for the same
  /// reason.
  static bool isWellFormed(String value) => isCanonical32ByteId(value);

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
}

/// Everything a v2 shared file link carries, parsed.
///
/// A payload exists only for a link that carries a `d` parameter this build can
/// read. A link without one - every link ArDrive has ever produced until now -
/// parses to `null`, and the recipient falls back to resolving the file over
/// GraphQL exactly as it does today.
///
/// Every field is independently optional: a link whose payload is nothing but
/// a header is valid, and so is one that lost its tail to a chat client. The
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

  /// The longest `d` this will even try to decode.
  ///
  /// The largest payload the builder can produce is a little over 900
  /// characters - every id, a 255 byte name and a 255 byte content type - so
  /// this is roughly double that and still far short of anything worth
  /// allocating for. A megabyte of `d` pasted into the address bar is not a
  /// link; it is something else, and it stops here rather than in the decoder.
  static const maxEncodedLength = 2048;

  /// Cipher names this schema accepts for `c`.
  ///
  /// Derived from the codes the payload actually spells, so a cipher the wire
  /// format cannot carry can never be advertised as one it can.
  static final supportedCiphers = _cipherCodes.keys.toSet();

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
  /// when they carry no `d` this build can read.
  ///
  /// Unknown parameters are ignored. Inside the payload, every field that fails
  /// validation is dropped on its own, logged, and leaves the rest intact.
  static SharedFileLinkPayload? tryParseParameters(
    Map<String, String> parameters, {
    SharedFileLinkKey? key,
  }) {
    final encoded = parameters[SharedFileLinkParams.payload];

    if (encoded == null || encoded.isEmpty) {
      // No payload is a v1 link: today's GraphQL resolution path, which cannot
      // be wrong about anything because the link asserted nothing. This is also
      // where a link written in a schema this build has never seen lands.
      return null;
    }

    return decode(
      encoded,
      key: key ?? SharedFileLinkKey.resolveFromParameters(parameters),
    );
  }

  /// The query parameters for this payload.
  ///
  /// [includeKey] writes the key as `k`. It is only ever legal for a URL whose
  /// query is not sent to a server - which today means the hash route, and
  /// after Phase 3 means nothing at all. Default off, and off is what the
  /// share dialog uses unless the sharer opts in.
  ///
  /// The key is never part of [encode]: it has to be placeable in a fragment
  /// independently of everything else the link says (§1.2), and a secret that
  /// can only travel welded to the payload is a secret that will one day travel
  /// where the payload goes.
  Map<String, String> toQueryParameters({bool includeKey = false}) {
    final parameters = <String, String>{
      SharedFileLinkParams.payload: encode(),
    };

    final rawKey = key.raw;

    if (includeKey && rawKey != null && rawKey.isNotEmpty) {
      parameters[SharedFileLinkParams.key] = rawKey;
    }

    return parameters;
  }

  /// This payload packed into the value of the `d` parameter.
  ///
  /// ## Why it is packed rather than spelled out
  ///
  /// The readable form of this schema - `?v=2&dtx=…&mtx=…&own=…&n=…&s=…&ct=…`
  /// - spends about 40 characters on parameter names and separators before it
  /// carries anything. Packing recovers those. What packing does *not* do is
  /// make the ids smaller: base64url of raw bytes is exactly as dense as a 43
  /// character id already was, so three ids cost 128 characters either way.
  /// That is why the measured saving is around 15% rather than half, and why
  /// the fields worth arguing about are which ids travel at all - see §1.2.
  ///
  /// ## Layout
  ///
  /// ```text
  /// byte 0     schema version, always [currentVersion]
  /// byte 1     flags
  ///              bit 0     pin
  ///              bit 1     hid
  ///              bits 2-3  cipher: 0 absent, 1 AES256-GCM, 2 AES256-CTR
  ///              bits 4-7  reserved, ignored on the way in
  /// byte 2     which fixed fields follow, read in ascending bit order
  ///              bit 0  dtx  32 bytes
  ///              bit 1  mtx  32 bytes
  ///              bit 2  own  32 bytes
  ///              bit 3  iv   12 bytes
  ///              bit 4  s    one length byte (1-6) then big endian bytes
  ///              bit 5  n    one length byte then UTF-8
  ///              bit 6  ct   one code byte; 0 means a length byte and UTF-8
  ///                          follow, anything else is a content type table
  ///                          index
  ///              bit 7  records follow
  /// bytes 3..  the fields the bitmap named, in bit order
  /// then       records to the end of the payload: tag, length, length bytes
  ///              tag 1  in   32 bytes
  ///              tag 2  thn  32 bytes
  ///              any other tag is skipped by its length
  /// ```
  ///
  /// ## How it degrades
  ///
  /// Every field is skippable by something the reader has already seen: a fixed
  /// field by its known width, a variable one by its length byte, a record by
  /// its length byte. So the reader stops exactly where the damage is and keeps
  /// everything before it - a link truncated by a chat client still paints the
  /// fields that fit, and a record from a newer build is stepped over rather
  /// than guessed at.
  ///
  /// ## How to extend it
  ///
  /// Add a record tag and leave [currentVersion] alone. Older builds skip the
  /// tag and keep every other field, which is this file's degradation rule
  /// applied to the wire format. Bump the version only for a change that
  /// reshapes the header, and accept what that costs: a build that does not
  /// recognise the version drops the payload whole and resolves the file over
  /// GraphQL.
  String encode() {
    final body = BytesBuilder();
    final records = BytesBuilder();
    var present = 0;

    void putFixed(int bit, Uint8List? value) {
      if (value == null) {
        return;
      }

      present |= 1 << bit;
      body.add(value);
    }

    void putVariable(int bit, Uint8List? value) {
      if (value == null) {
        return;
      }

      present |= 1 << bit;
      body
        ..addByte(value.length)
        ..add(value);
    }

    void putRecord(int tag, Uint8List? value) {
      if (value == null) {
        return;
      }

      records
        ..addByte(tag)
        ..addByte(value.length)
        ..add(value);
    }

    putFixed(_bitDataTxId, _encodeId(dataTxId, SharedFileLinkParams.dataTxId));
    putFixed(
      _bitMetadataTxId,
      _encodeId(metadataTxId, SharedFileLinkParams.metadataTxId),
    );
    putFixed(_bitOwner, _encodeId(ownerAddress, SharedFileLinkParams.owner));
    putFixed(_bitCipherIv, _encodeCipherIv(cipherIv));
    putVariable(_bitSize, _encodeSize(size));
    putVariable(_bitName, _encodeText(_nameForLink(name), SharedFileLinkParams.name));

    final contentTypeField = _encodeContentType(contentType);

    if (contentTypeField != null) {
      present |= 1 << _bitContentType;
      body.add(contentTypeField);
    }

    putRecord(
      _recordBundledIn,
      _encodeId(bundledInTxId, SharedFileLinkParams.bundledIn),
    );
    putRecord(
      _recordThumbnailTxId,
      _encodeId(thumbnailTxId, SharedFileLinkParams.thumbnailTxId),
    );

    if (records.isNotEmpty) {
      present |= 1 << _bitRecords;
    }

    var flags = 0;

    if (isPinned) {
      flags |= _flagPinned;
    }

    if (detailsAreHidden) {
      flags |= _flagHidden;
    }

    final cipherCode = _cipherCodes[cipher];

    if (cipherCode != null) {
      flags |= cipherCode << _cipherShift;
    }

    final bytes = BytesBuilder()
      ..addByte(version & 0xff)
      ..addByte(flags)
      ..addByte(present)
      ..add(body.takeBytes())
      ..add(records.takeBytes());

    return _encodeBase64Url(bytes.takeBytes());
  }

  /// Reads a packed payload, or returns `null` when [value] is not one this
  /// build can read.
  ///
  /// Never throws, and never gives up on a whole payload for one bad field -
  /// see the degradation notes on [encode]. `null` means "treat this as a v1
  /// link", which is always a safe answer: the resolver then asks the chain
  /// for everything instead of believing the link.
  static SharedFileLinkPayload? decode(
    String value, {
    SharedFileLinkKey key = SharedFileLinkKey.absent,
  }) {
    if (value.isEmpty) {
      return null;
    }

    if (value.length > maxEncodedLength) {
      logger.w(
        'Ignoring the payload of a shared file link: ${value.length} '
        'characters exceeds the $maxEncodedLength character limit. Falling '
        'back to GraphQL resolution.',
      );

      return null;
    }

    final bytes = _decodePartialBase64Url(value);

    if (bytes == null || bytes.length < _headerLengthInBytes) {
      logger.w(
        'Ignoring the payload of a shared file link: it is not a readable '
        'base64url payload with a header. Falling back to GraphQL resolution.',
      );

      return null;
    }

    final version = bytes[0];

    if (version != currentVersion) {
      // A schema from a future release, or a payload damaged in its very first
      // byte. Both degrade to the v1 path, which resolves everything over
      // GraphQL and therefore cannot be wrong about anything the link claimed.
      logger.w(
        'Ignoring the payload of a shared file link: unsupported schema '
        'version. Falling back to GraphQL resolution.',
      );

      return null;
    }

    final flags = bytes[1];
    final present = bytes[2];
    final reader = _PackedReader(bytes, _headerLengthInBytes);

    // Order is the format: every field is found by having stepped over the one
    // before it, so these have to be read in bit order and cannot be inlined
    // into the constructor call, where the evaluation order is not the point.
    final dataTxId = reader.fixed(present, _bitDataTxId, _idLengthInBytes);
    final metadataTxId =
        reader.fixed(present, _bitMetadataTxId, _idLengthInBytes);
    final ownerAddress = reader.fixed(present, _bitOwner, _idLengthInBytes);
    final cipherIv =
        reader.fixed(present, _bitCipherIv, cipherIvLengthInBytes);
    final size = reader.variable(present, _bitSize);
    final name = reader.variable(present, _bitName);
    final contentType = _decodeContentType(reader, present);
    final records = _decodeRecords(reader, present);

    if (reader.isTruncated) {
      logger.w(
        'A shared file link ended mid-payload. Keeping the fields that '
        'arrived whole and resolving the rest from the file\'s own record.',
      );
    }

    return SharedFileLinkPayload(
      version: version,
      dataTxId: _decodeId(dataTxId, SharedFileLinkParams.dataTxId),
      metadataTxId: _decodeId(metadataTxId, SharedFileLinkParams.metadataTxId),
      ownerAddress: _decodeId(ownerAddress, SharedFileLinkParams.owner),
      name: sanitizeName(_decodeText(name, SharedFileLinkParams.name)),
      size: _decodeSize(size),
      contentType: contentType,
      cipher: _decodeCipher(flags),
      cipherIv: cipherIv == null ? null : _encodeBase64Url(cipherIv),
      isPinned: (flags & _flagPinned) != 0,
      bundledInTxId: _decodeId(
        records[_recordBundledIn],
        SharedFileLinkParams.bundledIn,
      ),
      thumbnailTxId: _decodeId(
        records[_recordThumbnailTxId],
        SharedFileLinkParams.thumbnailTxId,
      ),
      detailsAreHidden: (flags & _flagHidden) != 0,
      key: key,
    );
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

  // ---------------------------------------------------------------------------
  // The wire format
  // ---------------------------------------------------------------------------
  //
  // Layout and rationale live on [encode]. What follows is one encoder and one
  // decoder per field, kept next to each other so that a change to either is a
  // change the other cannot avoid noticing.

  /// Version, flags, bitmap.
  static const _headerLengthInBytes = 3;

  /// Every id in this schema is a 32 byte value.
  static const _idLengthInBytes = 32;

  /// A length byte holds 255, and both variable fields are bounded by it.
  static const _maxValueLengthInBytes = 255;

  /// The largest size the payload can spell, in bytes of the encoded integer.
  ///
  /// Six bytes is 256 TiB, which no file is, and stays inside the 53 bit
  /// integers the web build actually has - eight bytes would silently lose
  /// precision there rather than fail.
  static const _maxSizeLengthInBytes = 6;

  /// The largest file size the payload can carry: 2^48 - 1.
  static const _maxEncodableSize = 0xffffffffffff;

  static const _flagPinned = 0x01;
  static const _flagHidden = 0x02;
  static const _cipherShift = 2;
  static const _cipherMask = 0x03;

  /// Cipher codes for bits 2-3 of the flags byte. `0` is "no cipher in this
  /// link"; the fourth code is unassigned and reads as an unknown cipher.
  static const _cipherCodes = <String, int>{
    Cipher.aes256gcm: 1,
    Cipher.aes256ctr: 2,
  };

  static const _bitDataTxId = 0;
  static const _bitMetadataTxId = 1;
  static const _bitOwner = 2;
  static const _bitCipherIv = 3;
  static const _bitSize = 4;
  static const _bitName = 5;
  static const _bitContentType = 6;
  static const _bitRecords = 7;

  static const _recordBundledIn = 1;
  static const _recordThumbnailTxId = 2;

  /// The `ct` code that means "a literal content type follows".
  static const _contentTypeIsLiteral = 0;

  /// Ids, addresses and keys all decode through the same shape check, so an id
  /// that would not survive the round trip never enters a link.
  static Uint8List? _encodeId(String? value, String field) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (!isCanonical32ByteId(value)) {
      logger.w(
        'Dropped `$field` from a shared file link: not a canonical 43 '
        'character base64url id.',
      );

      return null;
    }

    final bytes = _decodeBase64Url(value);

    if (bytes == null || bytes.length != _idLengthInBytes) {
      logger.w(
        'Dropped `$field` from a shared file link: it does not encode '
        '$_idLengthInBytes bytes.',
      );

      return null;
    }

    return bytes;
  }

  static String? _decodeId(Uint8List? bytes, String field) {
    if (bytes == null) {
      return null;
    }

    if (bytes.length != _idLengthInBytes) {
      logger.w(
        'Dropped `$field` from a shared file link: ${bytes.length} bytes '
        'instead of $_idLengthInBytes.',
      );

      return null;
    }

    return _encodeBase64Url(bytes);
  }

  static Uint8List? _encodeCipherIv(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final bytes = _decodeBase64Url(value);

    if (bytes == null || bytes.length != cipherIvLengthInBytes) {
      logger.w(
        'Dropped `${SharedFileLinkParams.cipherIv}` from a shared file link: '
        'it does not encode $cipherIvLengthInBytes bytes.',
      );

      return null;
    }

    return bytes;
  }

  static String? _decodeCipher(int flags) {
    final code = (flags >> _cipherShift) & _cipherMask;

    if (code == 0) {
      return null;
    }

    for (final entry in _cipherCodes.entries) {
      if (entry.value == code) {
        return entry.key;
      }
    }

    // Falls back to reading the cipher tag off the transaction, which is
    // authoritative anyway.
    logger.w(
      'Dropped `${SharedFileLinkParams.cipher}` from a shared file link: '
      'unknown cipher.',
    );

    return null;
  }

  /// A file size as the fewest big endian bytes that spell it.
  static Uint8List? _encodeSize(int? value) {
    if (value == null) {
      return null;
    }

    if (value < 0 || value > _maxEncodableSize) {
      logger.w(
        'Dropped `${SharedFileLinkParams.size}` from a shared file link: it '
        'is not a file size this schema can carry.',
      );

      return null;
    }

    final bytes = <int>[];
    var remaining = value;

    do {
      bytes.insert(0, remaining % 256);
      remaining ~/= 256;
    } while (remaining > 0);

    return Uint8List.fromList(bytes);
  }

  static int? _decodeSize(Uint8List? bytes) {
    if (bytes == null) {
      return null;
    }

    if (bytes.isEmpty || bytes.length > _maxSizeLengthInBytes) {
      logger.w(
        'Dropped `${SharedFileLinkParams.size}` from a shared file link: '
        '${bytes.length} bytes is not a size this schema can carry.',
      );

      return null;
    }

    var size = 0;

    // Multiplication rather than a shift: on the web an `int` is a double, and
    // `<<` past 32 bits there is not the arithmetic this looks like.
    for (final byte in bytes) {
      size = size * 256 + byte;
    }

    return size;
  }


  /// A name in the shape the reader will actually keep.
  ///
  /// The two ends disagreed. [_encodeText] truncates to what one length byte
  /// can address - 255 *bytes* - while [sanitizeName] drops anything over
  /// [maxNameLength] *characters* on the way back in, and drops a name
  /// carrying control or direction characters outright. A 150 character name
  /// was therefore written into the link and then thrown away by the reader:
  /// bytes spent for nothing, and a recipient shown no name at all until the
  /// metadata resolves.
  ///
  /// Truncating beats dropping, which is [_encodeText]'s own rule: a shortened
  /// name still tells the recipient what they are looking at. A name the
  /// reader would reject for its characters is dropped here rather than
  /// carried, because there is no shortening that would make it acceptable.
  static String? _nameForLink(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    if (unsafeNameCharacterPattern.hasMatch(value)) {
      logger.w(
        'Dropped `${SharedFileLinkParams.name}` from a shared file link: it '
        'contains control or direction characters.',
      );

      return null;
    }

    if (value.length <= maxNameLength) {
      return value;
    }

    // Never between the halves of a rune - the same rule [_encodeText]
    // applies, for the same reason.
    var end = maxNameLength;

    while (end > 0 && _isHighSurrogate(value.codeUnitAt(end - 1))) {
      end -= 1;
    }

    return end == 0 ? null : value.substring(0, end);
  }

  /// UTF-8, truncated on a rune boundary to what one length byte can address.
  ///
  /// Truncating beats dropping - a shortened name hint still tells the
  /// recipient what they are looking at - and beats splitting a rune, which
  /// would hand the decoder bytes that are not text.
  static Uint8List? _encodeText(String? value, String field) {
    if (value == null || value.isEmpty) {
      return null;
    }

    var encoded = utf8.encode(value);

    if (encoded.length > _maxValueLengthInBytes) {
      logger.w(
        'Truncated `$field` in a shared file link: ${encoded.length} bytes '
        'exceeds the $_maxValueLengthInBytes byte limit.',
      );

      // A UTF-8 byte is never fewer than one character, so this is already
      // past the limit and the loop below is bounded by it rather than by how
      // long the string happens to be.
      var end = value.length < _maxValueLengthInBytes
          ? value.length
          : _maxValueLengthInBytes;

      while (end > 0) {
        // Never cut between the halves of a rune: encoding a lone surrogate
        // yields a replacement character, which is this file guessing at a
        // name rather than shortening one.
        if (_isHighSurrogate(value.codeUnitAt(end - 1))) {
          end -= 1;

          continue;
        }

        encoded = utf8.encode(value.substring(0, end));

        if (encoded.length <= _maxValueLengthInBytes) {
          break;
        }

        end -= 1;
      }

      if (end == 0) {
        return null;
      }
    }

    return Uint8List.fromList(encoded);
  }

  static bool _isHighSurrogate(int codeUnit) =>
      codeUnit >= 0xd800 && codeUnit <= 0xdbff;

  static String? _decodeText(Uint8List? bytes, String field) {
    if (bytes == null || bytes.isEmpty) {
      return null;
    }

    try {
      return utf8.decode(bytes);
    } on FormatException {
      // Not `allowMalformed`: a name repaired into replacement characters is a
      // wrong name shown confidently, and this file drops fields rather than
      // guessing at them. The value is never logged - `n` and `ct` are private
      // file secrets when they are embedded (rule 3).
      logger.w('Dropped `$field` from a shared file link: it is not UTF-8.');

      return null;
    }
  }

  /// The `ct` field: a table code, or a literal marker and a UTF-8 string.
  static Uint8List? _encodeContentType(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }

    final code = _contentTypeCodes[value];

    if (code != null) {
      return Uint8List.fromList([code]);
    }

    // Dropped rather than truncated, unlike a name: half a MIME type is not a
    // shorter MIME type, and the reader would only drop it again.
    if (value.length > maxContentTypeLength) {
      logger.w(
        'Dropped `${SharedFileLinkParams.contentType}` from a shared file '
        'link: ${value.length} characters exceeds the $maxContentTypeLength '
        'character limit.',
      );

      return null;
    }

    final encoded = _encodeText(value, SharedFileLinkParams.contentType);

    if (encoded == null || encoded.length > _maxValueLengthInBytes) {
      return null;
    }

    return Uint8List.fromList(
      [_contentTypeIsLiteral, encoded.length, ...encoded],
    );
  }

  static String? _decodeContentType(_PackedReader reader, int present) {
    final code = reader.byte(present, _bitContentType);

    if (code == null) {
      return null;
    }

    if (code != _contentTypeIsLiteral) {
      final known = code <= _contentTypeTable.length
          ? _contentTypeTable[code - 1]
          : null;

      if (known == null) {
        // A code from a table this build has not grown yet. The type is worth
        // one `getTransactionDetails` at preview time, which is exactly what a
        // link without `ct` already costs.
        logger.w(
          'Dropped `${SharedFileLinkParams.contentType}` from a shared file '
          'link: unknown content type code $code.',
        );
      }

      return known;
    }

    final length = reader.takeByte();

    if (length == null) {
      return null;
    }

    return sanitizeContentType(
      _decodeText(reader.take(length), SharedFileLinkParams.contentType),
    );
  }

  /// Reads the records that follow the fixed fields, keyed by tag.
  ///
  /// A tag this build does not know is stepped over by its length rather than
  /// guessed at, which is what lets a newer build add a field without breaking
  /// an older one. The first record of a tag wins; a repeat is a link that has
  /// been edited and the second value is no more trustworthy than the first.
  static Map<int, Uint8List> _decodeRecords(_PackedReader reader, int present) {
    final records = <int, Uint8List>{};

    if ((present & (1 << _bitRecords)) == 0) {
      return records;
    }

    while (!reader.isExhausted && !reader.isTruncated) {
      final tag = reader.takeByte();
      final length = reader.takeByte();

      if (tag == null || length == null) {
        break;
      }

      final value = reader.take(length);

      if (value == null) {
        break;
      }

      records.putIfAbsent(tag, () => value);
    }

    return records;
  }

  /// Base64url without padding, which is how every other id in a link is
  /// spelled and the only alphabet a chat client's link detector will not cut
  /// short.
  static String _encodeBase64Url(List<int> bytes) {
    final encoded = base64Url.encode(bytes);
    final padding = encoded.indexOf('=');

    return padding < 0 ? encoded : encoded.substring(0, padding);
  }

  /// Decodes base64url, or `null` when [value] is not exactly that.
  ///
  /// Strict on purpose. Everything with a fixed width - an id, an IV - decodes
  /// through here, and a decoder that quietly accepted a prefix would turn a
  /// mangled 20 character IV into a plausible 12 byte one.
  static Uint8List? _decodeBase64Url(String value) {
    if (value.isEmpty) {
      return null;
    }

    try {
      return base64Url.decode(base64Url.normalize(value));
    } on FormatException {
      // The reason is not logged and neither is the value: this decodes the
      // payload of a link, and the same routine decodes keys elsewhere in this
      // file (rule 3). The caller says what was dropped.
      return null;
    }
  }

  /// Decodes as much of a payload as arrived.
  ///
  /// A link cut in transit leaves a string that no longer ends on a byte
  /// boundary, and [_decodeBase64Url] answers that with `null`. The largest
  /// four character prefix always does end on one, so the second attempt keeps
  /// whatever survived the cut - which the length and record structure then
  /// turns into "the fields before the cut" rather than nothing at all.
  static Uint8List? _decodePartialBase64Url(String value) =>
      _decodeBase64Url(value) ??
      _decodeBase64Url(value.substring(0, value.length - value.length % 4));

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

/// Content types that travel as one byte instead of as their name.
///
/// A code is the entry's index plus one, so the first entry is `1` and `0` is
/// reserved for "a literal follows". Anything not in here is written out in
/// full, which still costs less than the readable schema did - so a missing
/// entry is a missed saving and never a lost field.
///
/// **This table is append-only.** Reordering it, or removing an entry, silently
/// changes what every link already sent means: `Q3 Report.pdf` arriving as
/// `image/jpeg` is not a decoding error anybody will notice until the preview
/// is wrong. New entries go on the end, and the type they name has to be
/// spelled exactly as ArFS stores it - the code round trips to this string, and
/// `SharedFileCubit` compares it against the file's own record.
const _contentTypeTable = <String>[
  // 1-10: what most ArDrive shares actually are.
  'application/pdf',
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
  'image/svg+xml',
  'image/heic',
  'image/tiff',
  'image/avif',
  // 11-15: video.
  'video/mp4',
  'video/quicktime',
  'video/webm',
  'video/x-matroska',
  'video/mpeg',
  // 16-22: audio.
  'audio/mpeg',
  'audio/aac',
  'audio/ogg',
  'audio/wav',
  'audio/x-wav',
  'audio/flac',
  'audio/x-flac',
  // 23-32: text and the code types the previewer already knows
  // (`lib/utils/constants.dart`).
  'text/plain',
  'text/csv',
  'text/markdown',
  'text/html',
  'text/css',
  'text/xml',
  'text/javascript',
  'application/json',
  'application/xml',
  'application/javascript',
  // 33-38: archives.
  'application/zip',
  'application/gzip',
  'application/x-tar',
  'application/x-7z-compressed',
  'application/x-rar-compressed',
  'application/octet-stream',
  // 39-48: documents. The Office types are the reason this table pays for
  // itself: the Word one below is 71 characters, 77 once it is a `&ct=`
  // parameter, and one byte here.
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'application/vnd.oasis.opendocument.text',
  'application/vnd.oasis.opendocument.spreadsheet',
  'application/rtf',
  'application/epub+zip',
  // 49-50: Arweave's own, and the mail the previewer parses.
  'application/x.arweave-manifest+json',
  'message/rfc822',
  // 51-64: the long tail worth a byte.
  'font/woff2',
  'font/ttf',
  'text/x-python',
  'text/x-java',
  'text/x-c',
  'text/x-go',
  'text/x-rust',
  'text/x-yaml',
  'application/x-yaml',
  'application/toml',
  'application/wasm',
  'image/x-icon',
  'text/vtt',
  'application/sql',
];

/// [_contentTypeTable] the way the encoder reads it.
final _contentTypeCodes = <String, int>{
  for (var index = 0; index < _contentTypeTable.length; index++)
    _contentTypeTable[index]: index + 1,
};

/// A cursor over a decoded payload that runs out rather than throwing.
///
/// Once a read has fallen off the end nothing else is read: the fields after a
/// cut are not merely absent, they are unlocatable, and returning whatever
/// bytes happen to be there would be worse than returning nothing.
/// [isTruncated] says that happened, so the caller can log it once.
class _PackedReader {
  _PackedReader(this._bytes, this._offset);

  final Uint8List _bytes;
  int _offset;
  bool _truncated = false;

  bool get isTruncated => _truncated;

  bool get isExhausted => _offset >= _bytes.length;

  /// The next [length] bytes, or `null` when there are not that many left.
  Uint8List? take(int length) {
    if (_truncated || length < 0 || _offset + length > _bytes.length) {
      _truncated = true;

      return null;
    }

    final value = Uint8List.sublistView(_bytes, _offset, _offset + length);

    _offset += length;

    return value;
  }

  /// The next byte, or `null` when there is none.
  int? takeByte() => take(1)?.first;

  /// A fixed width field, when [present] says it is there.
  Uint8List? fixed(int present, int bit, int length) =>
      (present & (1 << bit)) == 0 ? null : take(length);

  /// A length-prefixed field, when [present] says it is there.
  Uint8List? variable(int present, int bit) {
    if ((present & (1 << bit)) == 0) {
      return null;
    }

    final length = takeByte();

    return length == null ? null : take(length);
  }

  /// A single byte field, when [present] says it is there.
  int? byte(int present, int bit) =>
      (present & (1 << bit)) == 0 ? null : takeByte();
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
  final candidateKey = rawFileKey ?? payload?.key.raw;

  // The one combination that leaks a file key.
  //
  // On the hash route everything after `#` stays in the browser, so a key in
  // the query is never sent anywhere. On a path route that same query *is*
  // sent: to the host, into its access log, and out again in the `Referer` of
  // anything the page loads. Only a fragment is safe there.
  //
  // Stated as an assert because it is a programming error rather than a
  // runtime condition - there is no input that reaches it, only a call that
  // should not have been written - and it fires in every debug and test run,
  // which is where such a call would be made.
  assert(
    route != SharedFileLinkRoute.share ||
        keyPlacement == SharedFileLinkKeyPlacement.fragment ||
        candidateKey == null ||
        candidateKey.isEmpty,
    'A file key must not be placed in the query of a path route: unlike the '
    'hash route, that query is sent to the server. Use '
    'SharedFileLinkKeyPlacement.fragment.',
  );

  final path = route.pathFor(fileId);
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
/// Every value a v2 link carries is base64url - the packed payload and the key
/// alike - so this escapes nothing today and the link is byte for byte what the
/// encoder produced. It stays because "the builder escapes what it writes" is a
/// property worth keeping true by construction rather than by argument: the day
/// a parameter carries something else, the escaping is already there.
///
/// [Uri.encodeComponent] rather than [Uri.encodeQueryComponent] so that a space
/// would become `%20` and not `+`, which only decodes back to a space in
/// readers that know they are looking at a query.
String _encode(String value) => Uri.encodeComponent(value);
