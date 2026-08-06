import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/constants.dart';

/// How a transaction's bytes may be shown, decided in one place so that the
/// widgets never get to make the call themselves.
///
/// The rule the whole file is built around
/// (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3): **a transaction's own claim
/// about its type may only ever make us more careful, never less.** The
/// uploader wrote that claim, an attacker chooses the transaction id, and a
/// `Content-Type` tag costs nothing to lie in. So the claim can push content
/// *into* the sandboxed class, but only the bytes themselves can unlock an
/// inline renderer.
enum RawTransactionRenderer {
  /// `Image.memory` - decoded by Flutter, painted as a widget, no DOM.
  image,

  /// Rasterised to page images by `pdfx` and painted as widgets. A PDF's
  /// embedded JavaScript has nothing to run on, because nothing about it
  /// reaches the DOM.
  pdf,

  /// `MarkdownBody` - Flutter widgets, no markup injection.
  markdown,

  /// A `Text` widget. HTML and SVG that end up here are shown as *source*, and
  /// that is the whole of what "showing" them means.
  text,

  /// An `<audio>`/`<video>` element pointed at the gateway's per-transaction
  /// sandbox origin. Media elements cannot execute their payload, and the URL
  /// is not on this origin, so a file that turns out not to be media fails to
  /// play rather than doing anything.
  media,

  /// Script-capable: never rendered as itself on this origin. The page offers
  /// the gateway's sandbox origin instead, and shows the source text.
  sandboxed,

  /// Nothing we can safely decode. The download button is the whole offer.
  downloadOnly,
}

/// What the *bytes* are, as far as they can be made to prove it.
enum SniffedContentClass {
  image,
  pdf,
  media,

  /// A document a browser would parse as markup and could execute: HTML, SVG,
  /// or any XML (which can carry XSLT and XHTML).
  markup,

  /// Decodes as text and is not markup.
  text,

  /// Nothing recognised it.
  unknown,
}

/// The verdict of [sniffTransactionContent].
class TransactionContentSniff {
  const TransactionContentSniff(this.contentClass, {this.contentType});

  final SniffedContentClass contentClass;

  /// The MIME type the magic bytes *prove*, when they prove one. `null` for
  /// classes that magic bytes cannot name precisely (text, markup, unknown).
  final String? contentType;
}

/// What the page will do with a transaction, and why.
class RawTransactionPresentation {
  const RawTransactionPresentation({
    required this.renderer,
    this.contentType,
    this.claimIsContradicted = false,
    this.offersSandboxedOpen = false,
  });

  final RawTransactionRenderer renderer;

  /// The type the page will *say* this is: what the bytes proved, when they
  /// proved anything, and only otherwise what the transaction claimed.
  final String? contentType;

  /// Whether the bytes proved a type that the transaction's own claim
  /// disagrees with. Never changes what is rendered - the bytes already decided
  /// that - but the page says so out loud.
  final bool claimIsContradicted;

  /// Whether to offer the gateway's per-transaction sandbox origin. Always true
  /// for content this page will not render itself.
  final bool offersSandboxedOpen;
}

/// Types a browser executes, or executes something on behalf of.
///
/// `text/xml` and `application/xml` are here because an XML document can carry
/// an XSLT stylesheet and can be XHTML; nothing is lost by treating them
/// carefully, since the sandboxed class still shows their source.
const Set<String> scriptCapableContentTypes = {
  'text/html',
  'application/xhtml+xml',
  'image/svg+xml',
  'text/xml',
  'application/xml',
};

/// A manifest is JSON, and is shown as JSON. It is called out because a gateway
/// will also serve it *as a site*, which is a thing a reader may well want and
/// which may only ever happen on the gateway's own origin.
const String arweaveManifestContentType = 'application/x.arweave-manifest+json';

/// Text types that are pretty-printed rather than shown verbatim.
const Set<String> _jsonContentTypes = {
  'application/json',
  'text/json',
  arweaveManifestContentType,
};

const Set<String> _markdownContentTypes = {
  'text/markdown',
  'text/x-markdown',
};

/// The largest transaction this page will pull into memory to look at.
///
/// Reuses the document preview's cap rather than inventing a second number: a
/// viewer for *arbitrary* transactions is the last place that should be
/// generous with a stranger's bytes. Anything bigger is download-only, and the
/// gateway sandbox origin is offered for reading it in a browser instead.
const int rawTransactionInlineMaxBytes = documentPreviewMaxFileSize;

/// The largest text this page will try to pretty-print as JSON.
const int _jsonPrettyPrintMaxBytes = 1024 * 1024;

/// How much of a file is examined before calling it text.
const int _textSniffWindow = 1024 * 64;

/// Strips parameters and case from a `Content-Type`, or returns `null` when
/// there is nothing usable left.
String? normaliseContentType(String? contentType) {
  if (contentType == null) {
    return null;
  }

  final normalised = contentType.split(';').first.trim().toLowerCase();

  return normalised.isEmpty ? null : normalised;
}

bool _isMediaContentType(String? contentType) =>
    contentType != null &&
    (contentType.startsWith('video/') || contentType.startsWith('audio/'));

/// Decides what to do with a transaction.
///
/// [sniff] is `null` when no bytes were fetched - either because the claim
/// named media (which streams rather than buffers) or because the transaction
/// is bigger than [rawTransactionInlineMaxBytes].
RawTransactionPresentation decidePresentation({
  required String? claimedContentType,
  required TransactionContentSniff? sniff,
  bool isOversized = false,
}) {
  final claim = normaliseContentType(claimedContentType);

  // Too big to look at. Nothing was verified, so nothing is rendered.
  if (isOversized) {
    return RawTransactionPresentation(
      renderer: RawTransactionRenderer.downloadOnly,
      contentType: claim,
      offersSandboxedOpen: true,
    );
  }

  if (sniff == null) {
    // Media is the one renderer a claim alone may select. It is not a decoder:
    // the element is handed a URL on the gateway's per-transaction origin, and
    // a file that is not media simply fails to play. Nothing about the bytes
    // reaches this origin, so a lie here costs a broken player and nothing
    // else.
    if (_isMediaContentType(claim)) {
      return RawTransactionPresentation(
        renderer: RawTransactionRenderer.media,
        contentType: claim,
        offersSandboxedOpen: true,
      );
    }

    return RawTransactionPresentation(
      renderer: RawTransactionRenderer.downloadOnly,
      contentType: claim,
      offersSandboxedOpen: true,
    );
  }

  final contradicted = _claimIsContradicted(claim, sniff);

  // The claim restricts. A transaction that says it is HTML is treated as HTML
  // whatever its bytes turn out to be, because the cheapest lie to tell is the
  // one that gets a file rendered as something safer than it is.
  if (claim != null && scriptCapableContentTypes.contains(claim)) {
    return RawTransactionPresentation(
      renderer: RawTransactionRenderer.sandboxed,
      contentType: claim,
      claimIsContradicted: contradicted,
      offersSandboxedOpen: true,
    );
  }

  switch (sniff.contentClass) {
    // The bytes restrict too, in the same direction: markup is markup no matter
    // what the transaction called it.
    case SniffedContentClass.markup:
      return RawTransactionPresentation(
        renderer: RawTransactionRenderer.sandboxed,
        contentType: claim ?? 'text/html',
        claimIsContradicted: contradicted,
        offersSandboxedOpen: true,
      );

    case SniffedContentClass.image:
      final sniffed = sniff.contentType;

      // Only the image types the app already decodes. An image format Flutter
      // cannot decode is a download, not a broken box.
      if (sniffed != null &&
          supportedImageTypesInFilePreview.contains(sniffed)) {
        return RawTransactionPresentation(
          renderer: RawTransactionRenderer.image,
          contentType: sniffed,
          claimIsContradicted: contradicted,
        );
      }

      return RawTransactionPresentation(
        renderer: RawTransactionRenderer.downloadOnly,
        contentType: sniffed ?? claim,
        claimIsContradicted: contradicted,
        offersSandboxedOpen: true,
      );

    case SniffedContentClass.pdf:
      return RawTransactionPresentation(
        renderer: RawTransactionRenderer.pdf,
        contentType: sniff.contentType,
        claimIsContradicted: contradicted,
      );

    case SniffedContentClass.media:
      return RawTransactionPresentation(
        renderer: RawTransactionRenderer.media,
        contentType: sniff.contentType,
        claimIsContradicted: contradicted,
        offersSandboxedOpen: true,
      );

    case SniffedContentClass.text:
      final isManifest = claim == arweaveManifestContentType;

      return RawTransactionPresentation(
        // Markdown is a *rendering* choice within text, and the worst a lie can
        // buy is having plain text rendered with headings: `MarkdownBody`
        // builds Flutter widgets and never injects markup.
        renderer: claim != null && _markdownContentTypes.contains(claim)
            ? RawTransactionRenderer.markdown
            : RawTransactionRenderer.text,
        contentType: claim ?? 'text/plain',
        claimIsContradicted: contradicted,
        // A manifest reads as JSON here and as a *site* on the gateway. The
        // second is only ever offered, never done here.
        offersSandboxedOpen: isManifest,
      );

    case SniffedContentClass.unknown:
      return RawTransactionPresentation(
        renderer: RawTransactionRenderer.downloadOnly,
        contentType: claim,
        claimIsContradicted: contradicted,
        offersSandboxedOpen: true,
      );
  }
}

/// Whether the transaction's claim disagrees with what the bytes proved.
///
/// Only a *proof* counts. Text and markup are shapes, not types, so a file that
/// merely decodes as text never contradicts anything - there is nothing to
/// contradict it with.
bool _claimIsContradicted(String? claim, TransactionContentSniff sniff) {
  // `application/octet-stream` claims nothing - it is the type a tool writes
  // when it does not know - so it cannot disagree with anything either.
  if (claim == null || claim == 'application/octet-stream') {
    return false;
  }

  if (sniff.contentClass == SniffedContentClass.markup) {
    return !scriptCapableContentTypes.contains(claim);
  }

  final sniffed = sniff.contentType;

  if (sniffed == null) {
    return false;
  }

  return claim != sniffed;
}

/// Reads the file's own magic bytes.
///
/// Everything here is a positive identification from the leading bytes: this is
/// the only input to the dispatch that an uploader cannot simply assert.
TransactionContentSniff sniffTransactionContent(Uint8List bytes) {
  if (bytes.isEmpty) {
    return const TransactionContentSniff(SniffedContentClass.unknown);
  }

  final proven = _sniffMagicBytes(bytes);

  if (proven != null) {
    return proven;
  }

  if (_looksLikeMarkup(bytes)) {
    return const TransactionContentSniff(SniffedContentClass.markup);
  }

  if (_looksLikeText(bytes)) {
    return const TransactionContentSniff(SniffedContentClass.text);
  }

  // Checked after the text test on purpose: `BM` is two perfectly ordinary
  // letters, and a text file that opens with them is not a bitmap.
  if (_startsWith(bytes, const [0x42, 0x4d]) && bytes.length >= 14) {
    return const TransactionContentSniff(
      SniffedContentClass.image,
      contentType: 'image/bmp',
    );
  }

  return const TransactionContentSniff(SniffedContentClass.unknown);
}

TransactionContentSniff? _sniffMagicBytes(Uint8List bytes) {
  if (_startsWith(
    bytes,
    const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
  )) {
    return const TransactionContentSniff(
      SniffedContentClass.image,
      contentType: 'image/png',
    );
  }

  if (_startsWith(bytes, const [0xff, 0xd8, 0xff])) {
    return const TransactionContentSniff(
      SniffedContentClass.image,
      contentType: 'image/jpeg',
    );
  }

  if (_startsWithAscii(bytes, 'GIF87a') || _startsWithAscii(bytes, 'GIF89a')) {
    return const TransactionContentSniff(
      SniffedContentClass.image,
      contentType: 'image/gif',
    );
  }

  if (_startsWithAscii(bytes, '%PDF-')) {
    return const TransactionContentSniff(
      SniffedContentClass.pdf,
      contentType: 'application/pdf',
    );
  }

  if (_startsWithAscii(bytes, 'RIFF') && bytes.length >= 12) {
    if (_asciiAt(bytes, 8, 'WEBP')) {
      return const TransactionContentSniff(
        SniffedContentClass.image,
        contentType: 'image/webp',
      );
    }

    if (_asciiAt(bytes, 8, 'WAVE')) {
      return const TransactionContentSniff(
        SniffedContentClass.media,
        contentType: 'audio/x-wav',
      );
    }
  }

  // ISO base media (`….ftyp…`): MP4, M4A, MOV and friends.
  if (bytes.length >= 12 && _asciiAt(bytes, 4, 'ftyp')) {
    return const TransactionContentSniff(
      SniffedContentClass.media,
      contentType: 'video/mp4',
    );
  }

  if (_startsWith(bytes, const [0x1a, 0x45, 0xdf, 0xa3])) {
    return const TransactionContentSniff(
      SniffedContentClass.media,
      contentType: 'video/webm',
    );
  }

  if (_startsWithAscii(bytes, 'OggS')) {
    return const TransactionContentSniff(
      SniffedContentClass.media,
      contentType: 'audio/ogg',
    );
  }

  if (_startsWithAscii(bytes, 'fLaC')) {
    return const TransactionContentSniff(
      SniffedContentClass.media,
      contentType: 'audio/x-flac',
    );
  }

  if (_startsWithAscii(bytes, 'ID3') ||
      _startsWith(bytes, const [0xff, 0xfb]) ||
      _startsWith(bytes, const [0xff, 0xf3]) ||
      _startsWith(bytes, const [0xff, 0xf2])) {
    return const TransactionContentSniff(
      SniffedContentClass.media,
      contentType: 'audio/mpeg',
    );
  }

  return null;
}

/// Whether the document opens with markup a browser would parse.
///
/// Deliberately blunt: anything whose first non-blank characters open an HTML
/// document, an SVG, an XML declaration or a doctype is markup. Being wrong in
/// this direction costs a reader the difference between "source shown with an
/// Open sandboxed button" and "source shown"; being wrong in the other
/// direction is the whole thing this page exists to prevent.
bool _looksLikeMarkup(Uint8List bytes) {
  final head = _leadingAscii(bytes, 1024).trimLeft().toLowerCase();

  if (head.isEmpty) {
    return false;
  }

  return head.startsWith('<!doctype') ||
      head.startsWith('<html') ||
      head.startsWith('<svg') ||
      head.startsWith('<?xml') ||
      head.startsWith('<!--') ||
      head.startsWith('<script');
}

/// Whether the file decodes as text.
///
/// A NUL or a stray control byte anywhere in the window means binary: no text
/// format this page renders contains one, and every binary format this page
/// does not recognise contains several.
bool _looksLikeText(Uint8List bytes) {
  final window = bytes.length > _textSniffWindow
      ? Uint8List.sublistView(bytes, 0, _textSniffWindow)
      : bytes;

  for (final byte in window) {
    if (byte == 0x09 || byte == 0x0a || byte == 0x0c || byte == 0x0d) {
      continue;
    }

    if (byte < 0x20 || byte == 0x7f) {
      return false;
    }
  }

  try {
    // A window cut mid-codepoint would fail a strict decode on a file that is
    // perfectly good text, so the last few bytes are dropped before deciding.
    final decodable = window.length == bytes.length
        ? window
        : Uint8List.sublistView(window, 0, window.length - 4);

    utf8.decode(decodable);

    return true;
  } catch (_) {
    return false;
  }
}

/// The text of a transaction that sniffed as text or markup.
///
/// JSON is pretty-printed when it parses and is small enough to be worth it;
/// everything else is returned exactly as it arrived, because for HTML and SVG
/// the source *is* the rendering.
String decodeTransactionText(Uint8List bytes, {String? contentType}) {
  final text = utf8.decode(bytes, allowMalformed: true);
  final claim = normaliseContentType(contentType);

  if (claim == null ||
      !_jsonContentTypes.contains(claim) ||
      bytes.length > _jsonPrettyPrintMaxBytes) {
    return text;
  }

  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(text));
  } catch (_) {
    // A file that says it is JSON and is not stays exactly what it is.
    return text;
  }
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }

  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) {
      return false;
    }
  }

  return true;
}

bool _startsWithAscii(Uint8List bytes, String prefix) =>
    _asciiAt(bytes, 0, prefix);

bool _asciiAt(Uint8List bytes, int offset, String expected) {
  if (bytes.length < offset + expected.length) {
    return false;
  }

  for (var i = 0; i < expected.length; i++) {
    if (bytes[offset + i] != expected.codeUnitAt(i)) {
      return false;
    }
  }

  return true;
}

String _leadingAscii(Uint8List bytes, int length) {
  final end = bytes.length < length ? bytes.length : length;
  final buffer = StringBuffer();

  for (var i = 0; i < end; i++) {
    final byte = bytes[i];

    // Skip a UTF-8 BOM and anything non-ASCII rather than guessing an encoding:
    // every marker this looks for is ASCII.
    if (byte < 0x80) {
      buffer.writeCharCode(byte);
    }
  }

  return buffer.toString();
}
