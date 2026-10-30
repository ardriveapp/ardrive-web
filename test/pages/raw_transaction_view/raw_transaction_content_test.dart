import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:flutter_test/flutter_test.dart';

/// The content-type dispatch of `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3.
///
/// Two rules are being held down here, and everything else is detail:
///
/// * only the **bytes** can unlock an inline renderer;
/// * a transaction's **claim** can only ever make the verdict stricter.
///
/// An attacker picks the transaction id, writes the `Content-Type` tag and
/// writes the `ct` in the link. Every test below is that attacker trying to get
/// something rendered as something safer than it is.
void main() {
  Uint8List bytes(List<int> values) => Uint8List.fromList(values);

  Uint8List ascii(String text) => Uint8List.fromList(utf8.encode(text));

  final png = bytes([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
  ]);
  final jpeg = bytes([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
  final gif = ascii('GIF89a...........');
  final pdf = ascii('%PDF-1.7\n1 0 obj\n');
  final mp4 = bytes([
    0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70, //
    0x6d, 0x70, 0x34, 0x32,
  ]);
  final html = ascii('<!DOCTYPE html><html><body><script>x()</script>');
  final svg = ascii('<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>');
  final plainText = ascii('the quick brown fox\njumped over the lazy dog\n');
  final json = ascii('{"a":1,"b":[2,3]}');
  final randomBinary = bytes(List.generate(64, (i) => (i * 37) % 256));

  group('sniffTransactionContent proves what it can from the bytes', () {
    test('images', () {
      expect(sniffTransactionContent(png).contentType, 'image/png');
      expect(sniffTransactionContent(jpeg).contentType, 'image/jpeg');
      expect(sniffTransactionContent(gif).contentType, 'image/gif');
    });

    test('pdf', () {
      final sniff = sniffTransactionContent(pdf);

      expect(sniff.contentClass, SniffedContentClass.pdf);
      expect(sniff.contentType, 'application/pdf');
    });

    test('media containers', () {
      expect(sniffTransactionContent(mp4).contentClass,
          SniffedContentClass.media);
      expect(sniffTransactionContent(ascii('OggS.......')).contentClass,
          SniffedContentClass.media);
    });

    test('markup, whatever it calls itself', () {
      expect(sniffTransactionContent(html).contentClass,
          SniffedContentClass.markup);
      expect(sniffTransactionContent(svg).contentClass,
          SniffedContentClass.markup);
      expect(
        sniffTransactionContent(ascii('<?xml version="1.0"?><root/>'))
            .contentClass,
        SniffedContentClass.markup,
      );
    });

    test('text, and not markup', () {
      expect(sniffTransactionContent(plainText).contentClass,
          SniffedContentClass.text);
      expect(
        sniffTransactionContent(json).contentClass,
        SniffedContentClass.text,
      );
    });

    test('nothing at all, for bytes it does not recognise', () {
      expect(
        sniffTransactionContent(randomBinary).contentClass,
        SniffedContentClass.unknown,
      );
      expect(
        sniffTransactionContent(bytes([])).contentClass,
        SniffedContentClass.unknown,
      );
    });
  });

  group('inline-safe types render inline', () {
    test('an image the app can decode', () {
      final presentation = decidePresentation(
        claimedContentType: 'image/png',
        sniff: sniffTransactionContent(png),
      );

      expect(presentation.renderer, RawTransactionRenderer.image);
      expect(presentation.contentType, 'image/png');
      expect(presentation.offersSandboxedOpen, isFalse);
      expect(presentation.claimIsContradicted, isFalse);
    });

    test('a PDF, because the rasteriser puts pixels on screen and not a DOM',
        () {
      final presentation = decidePresentation(
        claimedContentType: 'application/pdf',
        sniff: sniffTransactionContent(pdf),
      );

      expect(presentation.renderer, RawTransactionRenderer.pdf);
      expect(presentation.offersSandboxedOpen, isFalse);
    });

    test('plain text', () {
      final presentation = decidePresentation(
        claimedContentType: 'text/plain',
        sniff: sniffTransactionContent(plainText),
      );

      expect(presentation.renderer, RawTransactionRenderer.text);
      expect(presentation.offersSandboxedOpen, isFalse);
    });

    test('markdown, which is a rendering choice within text', () {
      final presentation = decidePresentation(
        claimedContentType: 'text/markdown',
        sniff: sniffTransactionContent(ascii('# Title\n\nbody')),
      );

      expect(presentation.renderer, RawTransactionRenderer.markdown);
    });

    test('media, from a claim, because no byte of it is fetched at all', () {
      for (final claim in ['video/mp4', 'audio/mpeg']) {
        final presentation =
            decidePresentation(claimedContentType: claim, sniff: null);

        expect(presentation.renderer, RawTransactionRenderer.media);
        // The player is pointed at the gateway's per-transaction origin, so the
        // escape hatch for a file that will not play is always there.
        expect(presentation.offersSandboxedOpen, isTrue);
      }
    });
  });

  group('script-capable content is never rendered inline', () {
    test('HTML goes to the sandbox, by its bytes', () {
      final presentation = decidePresentation(
        claimedContentType: 'text/html',
        sniff: sniffTransactionContent(html),
      );

      expect(presentation.renderer, RawTransactionRenderer.sandboxed);
      expect(presentation.offersSandboxedOpen, isTrue);
    });

    test('SVG goes to the sandbox and stays off the image allowlist', () {
      final presentation = decidePresentation(
        claimedContentType: 'image/svg+xml',
        sniff: sniffTransactionContent(svg),
      );

      expect(presentation.renderer, RawTransactionRenderer.sandboxed);
      expect(presentation.renderer, isNot(RawTransactionRenderer.image));
    });

    test('HTML dressed as a PNG is still HTML', () {
      final presentation = decidePresentation(
        claimedContentType: 'image/png',
        sniff: sniffTransactionContent(html),
      );

      expect(presentation.renderer, RawTransactionRenderer.sandboxed);
      expect(presentation.claimIsContradicted, isTrue);
    });

    test('SVG dressed as plain text is still SVG', () {
      final presentation = decidePresentation(
        claimedContentType: 'text/plain',
        sniff: sniffTransactionContent(svg),
      );

      expect(presentation.renderer, RawTransactionRenderer.sandboxed);
      expect(presentation.claimIsContradicted, isTrue);
    });

    test('a PNG claiming to be HTML is treated as HTML, not as a PNG', () {
      // The claim only ever restricts. Rendering an image here would cost
      // nothing; the rule is worth more than the one preview it loses.
      final presentation = decidePresentation(
        claimedContentType: 'text/html',
        sniff: sniffTransactionContent(png),
      );

      expect(presentation.renderer, RawTransactionRenderer.sandboxed);
      expect(presentation.claimIsContradicted, isTrue);
    });

    test('XML is treated as markup, because XML can carry XSLT and XHTML', () {
      final presentation = decidePresentation(
        claimedContentType: 'application/xml',
        sniff: sniffTransactionContent(ascii('<?xml version="1.0"?><a/>')),
      );

      expect(presentation.renderer, RawTransactionRenderer.sandboxed);
    });
  });

  group('anything we cannot decode is download-only', () {
    test('unrecognised bytes', () {
      final presentation = decidePresentation(
        claimedContentType: null,
        sniff: sniffTransactionContent(randomBinary),
      );

      expect(presentation.renderer, RawTransactionRenderer.downloadOnly);
      expect(presentation.offersSandboxedOpen, isTrue);
    });

    test('an unknown claimed type over unrecognised bytes', () {
      final presentation = decidePresentation(
        claimedContentType: 'application/octet-stream',
        sniff: sniffTransactionContent(randomBinary),
      );

      expect(presentation.renderer, RawTransactionRenderer.downloadOnly);
    });

    test('an encrypted blob, which is what /view v1 does with private bytes',
        () {
      // §1.3: `/view` accepts no `c`/`iv`/`k`, so ciphertext arrives as bytes
      // nobody can read. That must be a download card, never a guess.
      final ciphertext = bytes(List.generate(512, (i) => (i * 131 + 7) % 256));

      expect(
        decidePresentation(
          claimedContentType: 'application/octet-stream',
          sniff: sniffTransactionContent(ciphertext),
        ).renderer,
        RawTransactionRenderer.downloadOnly,
      );
    });

    test('an image format the sniffer does not recognise', () {
      // TIFF is a real image and is not on the app's decode allowlist, so it
      // never reaches an inline renderer: a download beats a broken box, and
      // "we could not identify this" is the honest reason.
      final tiff = bytes([0x49, 0x49, 0x2a, 0x00, 0x08, 0x00, 0x00, 0x00]);

      expect(
        decidePresentation(
          claimedContentType: 'image/tiff',
          sniff: sniffTransactionContent(tiff),
        ).renderer,
        RawTransactionRenderer.downloadOnly,
      );
    });

    test('a transaction too big to have been looked at', () {
      final presentation = decidePresentation(
        claimedContentType: 'image/png',
        sniff: null,
        isOversized: true,
      );

      expect(presentation.renderer, RawTransactionRenderer.downloadOnly);
      expect(presentation.offersSandboxedOpen, isTrue);
    });
  });

  group('manifests', () {
    test('read as JSON here and are only ever *offered* as a site', () {
      final presentation = decidePresentation(
        claimedContentType: 'application/x.arweave-manifest+json',
        sniff: sniffTransactionContent(json),
      );

      expect(presentation.renderer, RawTransactionRenderer.text);
      expect(presentation.offersSandboxedOpen, isTrue);
    });
  });

  group('decodeTransactionText', () {
    test('pretty-prints JSON', () {
      expect(
        decodeTransactionText(json, contentType: 'application/json'),
        '{\n  "a": 1,\n  "b": [\n    2,\n    3\n  ]\n}',
      );
    });

    test('leaves markup exactly as it arrived, because the source is the point',
        () {
      expect(
        decodeTransactionText(html, contentType: 'text/html'),
        '<!DOCTYPE html><html><body><script>x()</script>',
      );
    });

    test('survives bytes that are not valid UTF-8', () {
      expect(
        () => decodeTransactionText(bytes([0xc3, 0x28, 0x41])),
        returnsNormally,
      );
    });
  });
}
