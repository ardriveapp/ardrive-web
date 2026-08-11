part of 'raw_transaction_view_cubit.dart';

@immutable
abstract class RawTransactionViewState extends Equatable {
  const RawTransactionViewState();

  @override
  List<Object?> get props => [];
}

/// RESOLVING - the transaction is being described and fetched.
///
/// Carries the link's own hints so the card can paint a name before anything
/// has answered, exactly as the share page does with a v2 payload.
class RawTransactionLoadInProgress extends RawTransactionViewState {
  const RawTransactionLoadInProgress({this.name, this.contentType});

  final String? name;
  final String? contentType;

  @override
  List<Object?> get props => [name, contentType];
}

/// ERROR_LINK - the path segment is not a transaction id.
///
/// Nothing is fetched, nothing is retried, and no subdomain is built from it:
/// a 43-character base64url string is the entry condition for every other
/// state in this file.
class RawTransactionLinkDamaged extends RawTransactionViewState {
  const RawTransactionLinkDamaged();
}

/// NOT_FOUND - every gateway answered 404.
class RawTransactionNotFound extends RawTransactionViewState {
  const RawTransactionNotFound();
}

/// ERROR_NETWORK - the gateways could not be reached, or answered with
/// something that was not the transaction.
class RawTransactionLoadFailure extends RawTransactionViewState {
  const RawTransactionLoadFailure();
}

/// READY - the transaction is on screen, rendered the way
/// [RawTransactionPresentation] said it may be.
class RawTransactionReady extends RawTransactionViewState {
  const RawTransactionReady({
    required this.txId,
    required this.presentation,
    required this.sandboxUrl,
    this.name,
    this.size,
    this.ownerAddress,
    this.bytes,
    this.text,
    this.isOversized = false,
  });

  final String txId;

  /// What may be rendered, and why. Everything the view switches on lives here
  /// so that no widget re-derives the decision from a content type.
  final RawTransactionPresentation presentation;

  /// `https://{base32(txId)}.{gateway}/{txId}` - the only URL this page will
  /// point a browser, a media element or a frame at.
  final String sandboxUrl;

  /// The file name, sanitised, from the link's `n` hint or a naming tag. `null`
  /// when the transaction never carried one.
  final String? name;

  final int? size;

  final String? ownerAddress;

  /// The fetched bytes, present only when they were small enough to look at.
  final Uint8List? bytes;

  /// The decoded text, for the renderers that show text - including the source
  /// view of the sandboxed class, which is the *only* thing HTML and SVG ever
  /// get on this origin.
  final String? text;

  /// Whether the transaction was too big to examine, so nothing about it was
  /// verified.
  final bool isOversized;

  /// [bytes] is deliberately absent, and represented by its length instead: a
  /// state comparison must not walk 25 MiB element by element, and one load
  /// emits exactly one ready state anyway.
  @override
  List<Object?> get props => [
        txId,
        presentation.renderer,
        presentation.contentType,
        presentation.claimIsContradicted,
        presentation.offersSandboxedOpen,
        sandboxUrl,
        name,
        size,
        ownerAddress,
        bytes?.length,
        text,
        isOversized,
      ];
}
