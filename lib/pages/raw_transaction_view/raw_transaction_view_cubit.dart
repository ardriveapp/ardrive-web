import 'dart:async';

import 'package:ardrive/components/sandboxed_transaction_view/arweave_sandbox_url.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive/utils/validate_arweave_id.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

part 'raw_transaction_view_state.dart';

/// Resolves one arbitrary Arweave transaction for `/view/{txId}`.
///
/// This is the share page's state machine (`docs/FILE_SHARING_REDESIGN_PLAN.md`
/// §2) with the two states that need ArFS taken out: there is no `LOCKED`,
/// because `/view` v1 serves public content only, and no freshness check,
/// because a transaction is immutable and has no newer revision to offer.
///
/// What replaces them is the decision this page exists to make safely: *what
/// may be rendered*. An attacker chooses the transaction id, so the only inputs
/// trusted to unlock an inline renderer are the bytes themselves
/// ([sniffTransactionContent]); the transaction's own claims can restrict, and
/// nothing else. See [decidePresentation].
class RawTransactionViewCubit extends Cubit<RawTransactionViewState> {
  RawTransactionViewCubit({
    required this.txId,
    required ArweaveService arweave,
    this.nameHint,
    this.contentTypeHint,
  })  : _arweave = arweave,
        super(
          RawTransactionLoadInProgress(
            name: _sanitiseName(nameHint),
            contentType: normaliseContentType(contentTypeHint),
          ),
        ) {
    unawaited(load());
  }

  final String txId;

  /// The link's `n` - a filename the *sender* chose, so a display string and a
  /// save-dialog default, never a path and never a source of truth.
  final String? nameHint;

  /// The link's `ct`. One claim among several, and claims only ever restrict.
  final String? contentTypeHint;

  final ArweaveService _arweave;

  /// Incremented by every load, so a slow fetch from an abandoned load cannot
  /// emit over a newer one.
  int _resolution = 0;

  /// The load in flight, for tests that need to await it.
  Future<void>? get currentLoad => _currentLoad;
  Future<void>? _currentLoad;

  Future<void> retry() => load();

  Future<void> load() {
    final resolution = ++_resolution;
    final load = _load(resolution);

    _currentLoad = load;

    return load;
  }

  Future<void> _load(int resolution) async {
    final name = _sanitiseName(nameHint);
    final hintedType = normaliseContentType(contentTypeHint);

    // Nothing - not a request, not a subdomain, not a retry - happens for a
    // string that is not a transaction id. The route parser rejects those
    // already; this page is reachable from anywhere and does not assume it.
    if (!isArweaveTransactionID(txId)) {
      _emit(resolution, const RawTransactionLinkDamaged());

      return;
    }

    final sandboxUrl = arweaveSandboxUrl(
      txId: txId,
      // The configured data gateway, never a constant: a deployment pointed at
      // a private gateway must not quietly reach out to arweave.net.
      gatewayUrl: _arweave.client.api.gatewayUrl,
    );

    if (sandboxUrl == null) {
      _emit(resolution, const RawTransactionLinkDamaged());

      return;
    }

    _emit(
      resolution,
      RawTransactionLoadInProgress(name: name, contentType: hintedType),
    );

    final description = await _describe();

    final resolvedName = name ?? description?.name;
    final size = description?.size;
    final claim = _effectiveClaim([hintedType, description?.contentType]);

    RawTransactionReady ready({
      required RawTransactionPresentation presentation,
      Uint8List? bytes,
      String? text,
      bool isOversized = false,
    }) =>
        RawTransactionReady(
          txId: txId,
          presentation: presentation,
          sandboxUrl: sandboxUrl,
          name: resolvedName,
          size: size,
          ownerAddress: description?.ownerAddress,
          bytes: bytes,
          text: text,
          isOversized: isOversized,
        );

    // Media never gets buffered. The element is handed the gateway's
    // per-transaction origin and streams from there, which is both the only way
    // to play an hour of video and a stricter posture than fetching it: no byte
    // of it is ever on this origin at all.
    if (claim != null &&
        (claim.startsWith('video/') || claim.startsWith('audio/'))) {
      _emit(
        resolution,
        ready(
          presentation:
              decidePresentation(claimedContentType: claim, sniff: null),
        ),
      );

      return;
    }

    if (size != null && size > rawTransactionInlineMaxBytes) {
      _emit(
        resolution,
        ready(
          presentation: decidePresentation(
            claimedContentType: claim,
            sniff: null,
            isOversized: true,
          ),
          isOversized: true,
        ),
      );

      return;
    }

    final http.Response response;

    try {
      // The gateway-fallback waterfall (primary → GAR → arweave.net), never a
      // single hardcoded gateway: a blackholed primary must not be the whole
      // story for a link somebody was sent.
      response = await _arweave.gatewayFallback.fetchData(
        txId,
        _arweave.client,
      );
    } on TransactionNotFound {
      _emit(resolution, const RawTransactionNotFound());

      return;
    } catch (e) {
      logger.e('Could not fetch transaction $txId for the raw viewer', e);
      _emit(resolution, const RawTransactionLoadFailure());

      return;
    }

    final bytes = response.bodyBytes;
    final servedType = normaliseContentType(response.headers['content-type']);

    // A transaction GraphQL had no size for can still turn out to be enormous.
    if (bytes.length > rawTransactionInlineMaxBytes) {
      _emit(
        resolution,
        ready(
          presentation: decidePresentation(
            claimedContentType: _effectiveClaim([claim, servedType]),
            sniff: null,
            isOversized: true,
          ),
          isOversized: true,
        ),
      );

      return;
    }

    final sniff = sniffTransactionContent(bytes);
    final presentation = decidePresentation(
      // The gateway's own `Content-Type` joins the claims here rather than
      // replacing them, and by the rules of [_effectiveClaim] it can only make
      // the verdict stricter (§4.3: the served type is trusted for the
      // sandboxed classes, where a mislabel is contained by the sandbox).
      claimedContentType: _effectiveClaim([claim, servedType]),
      sniff: sniff,
    );

    _emit(
      resolution,
      ready(
        presentation: presentation,
        bytes: bytes,
        text: _rendersText(presentation.renderer)
            ? decodeTransactionText(
                bytes,
                contentType: presentation.contentType,
              )
            : null,
      ),
    );
  }

  bool _rendersText(RawTransactionRenderer renderer) =>
      renderer == RawTransactionRenderer.text ||
      renderer == RawTransactionRenderer.markdown ||
      // The sandboxed class shows its *source*, which is the entirety of what
      // HTML and SVG ever get on this origin.
      renderer == RawTransactionRenderer.sandboxed;

  /// One GraphQL call for the size, the claimed type and the owner.
  ///
  /// Never fatal: a gateway that has not indexed the transaction yet, or a
  /// GraphQL endpoint that is down, costs the page a size chip and an owner
  /// line - not the transaction.
  Future<_TransactionDescription?> _describe() async {
    try {
      // Bounded, because this one call sits in front of the fetch: it is what
      // tells us how big the transaction is before we agree to hold it in
      // memory. A GraphQL endpoint having a bad day costs five seconds, not the
      // page.
      final transaction = await _arweave
          .getInfoOfTxToBePinned(txId)
          .timeout(const Duration(seconds: 5));

      if (transaction == null) {
        return null;
      }

      final tags = {
        for (final tag in transaction.tags) tag.name.toLowerCase(): tag.value,
      };

      return _TransactionDescription(
        ownerAddress: transaction.owner.address,
        size: int.tryParse(transaction.data.size),
        contentType: normaliseContentType(
          transaction.data.type ?? tags['content-type'],
        ),
        // Neither tag is standardised; both are conventions that uploaders do
        // use, and a name is the whole difference between this page and a raw
        // gateway URL. Sanitised on the way in, like every other string a
        // stranger wrote.
        name: _sanitiseName(tags['file-name'] ?? tags['title']),
      );
    } catch (e) {
      logger.w('Could not describe transaction $txId for the raw viewer: $e');

      return null;
    }
  }

  /// Picks the claim the dispatch will be run against.
  ///
  /// A script-capable claim from *any* source wins, because the direction that
  /// matters is the strict one: a transaction served as `text/html` is HTML
  /// however sweetly its link described it. Otherwise the most specific claim
  /// wins - the link's hint, then the transaction's own tag, then the gateway's
  /// header.
  String? _effectiveClaim(List<String?> claims) {
    final present = claims.whereType<String>().toList();

    for (final claim in present) {
      if (scriptCapableContentTypes.contains(claim)) {
        return claim;
      }
    }

    return present.isEmpty ? null : present.first;
  }

  void _emit(int resolution, RawTransactionViewState state) {
    if (isClosed || resolution != _resolution) {
      return;
    }

    emit(state);
  }
}

/// What GraphQL knows about a transaction, if anything.
class _TransactionDescription {
  const _TransactionDescription({
    this.ownerAddress,
    this.size,
    this.contentType,
    this.name,
  });

  final String? ownerAddress;
  final int? size;
  final String? contentType;
  final String? name;
}

/// The longest name this page will show or save under.
const int _maxNameLength = 120;

/// Makes a stranger's filename safe to show and to save under.
///
/// Path separators are replaced because this string reaches a save dialog and a
/// name is not a path. Control and direction characters are not repaired at
/// all: a name carrying one is dropped, and the page falls back to the
/// transaction id - the one string here that is guaranteed to say what it is.
/// That is the same rule the shared file schema applies to its own `n`
/// ([SharedFileLinkPayload.unsafeNameCharacterPattern], which is also the
/// pattern), and it matters for the same reason: `Q3-Report<U+202E>fdp.exe`
/// reads as `Q3-Reportexe.pdf` in this card and in the operating system's save
/// dialog while landing on disk as an executable.
///
/// Nothing here is about rendering - a Flutter `Text` widget was never at risk
/// - and everything here is about the two places the string leaves Flutter for.
String? _sanitiseName(String? name) {
  if (name == null) {
    return null;
  }

  // Trimmed before the check, so that a tag with a stray trailing newline
  // keeps its name; a control character *inside* one is the deceptive case.
  final cleaned = name.replaceAll(RegExp(r'[/\\]'), '_').trim();

  if (cleaned.isEmpty || cleaned == '.' || cleaned == '..') {
    return null;
  }

  if (SharedFileLinkPayload.unsafeNameCharacterPattern.hasMatch(cleaned)) {
    logger.w(
      'Dropped the name of a transaction: it contains control or direction '
      'characters.',
    );

    return null;
  }

  return cleaned.length > _maxNameLength
      ? cleaned.substring(0, _maxNameLength)
      : cleaned;
}
