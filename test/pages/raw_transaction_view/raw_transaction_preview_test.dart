import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/components/sandboxed_transaction_view/sandboxed_transaction_view.dart';
import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive/pages/drive_detail/components/pdf_preview_widget.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_content.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_preview.dart';
import 'package:ardrive/pages/raw_transaction_view/raw_transaction_view_cubit.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

/// What each branch of the §4.3 dispatch actually puts on screen.
///
/// The decision itself is tested in `raw_transaction_content_test.dart`; this
/// file is about the other half of the promise - that the decision is the only
/// thing the widgets obey, and in particular that the script-capable branch
/// renders a *source view and a sandbox affordance*, never the content.
void main() {
  const txId = 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI';
  const sandboxUrl =
      'https://r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza'
      '.arweave.net/$txId';

  Uint8List ascii(String text) => Uint8List.fromList(utf8.encode(text));

  /// A real, complete 1x1 PNG, so the image branch is exercised with something
  /// Flutter can actually decode.
  final png = Uint8List.fromList([
    0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
    0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xde, 0x00, 0x00, 0x00, 0x0d, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9c, 0x63, 0xf8, 0xcf, 0xc0, 0xf0,
    0x1f, 0x00, 0x05, 0x00, 0x01, 0xff, 0x89, 0x99,
    0x3d, 0x1d, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45,
    0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
  ]);

  RawTransactionReady ready({
    required Uint8List? bytes,
    required String? claimedContentType,
    String? name,
    bool isOversized = false,
  }) {
    final sniff = bytes == null ? null : sniffTransactionContent(bytes);
    final presentation = decidePresentation(
      claimedContentType: claimedContentType,
      sniff: sniff,
      isOversized: isOversized,
    );

    return RawTransactionReady(
      txId: txId,
      presentation: presentation,
      sandboxUrl: sandboxUrl,
      name: name,
      bytes: bytes,
      text: bytes == null
          ? null
          : decodeTransactionText(bytes, contentType: presentation.contentType),
      isOversized: isOversized,
    );
  }

  Widget wrap(Widget child) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, RawTransactionReady state) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(
      RawTransactionPreview(
        state: state,
        // The real rasteriser needs pdf.js, and the real players need a media
        // plugin; neither exists in a VM test.
        pdfViewerBuilder: (context, bytes, onRenderFailed) =>
            const Text('rasterised pages'),
        mediaBuilder: (context, url, contentType) => Text('player for $url'),
      ),
    ));
    await tester.pump();
  }

  group('inline-safe types render inline', () {
    testWidgets('an image is decoded and painted, with no sandbox offer',
        (tester) async {
      await pump(
        tester,
        ready(bytes: png, claimedContentType: 'image/png'),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(SandboxedTransactionView), findsNothing);
    });

    testWidgets('a PDF is rasterised rather than handed to the browser',
        (tester) async {
      await pump(
        tester,
        ready(bytes: ascii('%PDF-1.7\n'), claimedContentType: 'application/pdf'),
      );

      expect(find.byType(PdfPreviewWidget), findsOneWidget);
      expect(find.text('rasterised pages'), findsOneWidget);
      expect(find.byType(SandboxedTransactionView), findsNothing);
    });

    testWidgets('text renders as text', (tester) async {
      await pump(
        tester,
        ready(
          bytes: ascii('a plain little file'),
          claimedContentType: 'text/plain',
        ),
      );

      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byType(SandboxedTransactionView), findsNothing);
    });

    testWidgets('markdown renders through Flutter widgets', (tester) async {
      await pump(
        tester,
        ready(
          bytes: ascii('# Title\n\nbody'),
          claimedContentType: 'text/markdown',
        ),
      );

      expect(find.byType(MarkdownBody), findsOneWidget);
    });

    testWidgets('media is pointed at the gateway sandbox origin',
        (tester) async {
      await pump(
        tester,
        ready(bytes: null, claimedContentType: 'video/mp4'),
      );

      expect(find.text('player for $sandboxUrl'), findsOneWidget);
      // The escape hatch stays, because a claim is all that put a player here.
      expect(find.byType(SandboxedTransactionView), findsOneWidget);
    });
  });

  group('script-capable types', () {
    testWidgets('HTML shows its source and offers the sandbox, and renders '
        'nothing of itself', (tester) async {
      await pump(
        tester,
        ready(
          bytes: ascii('<!DOCTYPE html><html><body><script>x()</script>'),
          claimedContentType: 'text/html',
        ),
      );

      // The sandbox affordance is there...
      expect(find.byType(SandboxedTransactionView), findsOneWidget);

      // ...the source is shown as source...
      expect(find.byType(DocumentPreviewWidget), findsOneWidget);
      expect(
        tester
            .widget<DocumentPreviewWidget>(find.byType(DocumentPreviewWidget))
            .contentType,
        // Never `text/html`: the one widget that decides between markup-ish
        // rendering and plain text is told, explicitly, that this is text.
        'text/plain',
      );

      // ...and nothing of the document itself was rendered.
      expect(find.byType(MarkdownBody), findsNothing);
      expect(find.byType(Image), findsNothing);
      expect(find.byType(HtmlElementView), findsNothing);
    });

    testWidgets('SVG is treated as markup, not as an image', (tester) async {
      await pump(
        tester,
        ready(
          bytes: ascii('<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>'),
          claimedContentType: 'image/svg+xml',
        ),
      );

      expect(find.byType(SandboxedTransactionView), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('HTML dressed as a PNG is still sandboxed, and says so',
        (tester) async {
      await pump(
        tester,
        ready(
          bytes: ascii('<html><body>not a png</body></html>'),
          claimedContentType: 'image/png',
        ),
      );

      expect(find.byType(SandboxedTransactionView), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('match'), findsOneWidget);
    });
  });

  group('unknown types', () {
    testWidgets('render nothing and offer a download and the gateway',
        (tester) async {
      await pump(
        tester,
        ready(
          bytes: Uint8List.fromList(List.generate(64, (i) => (i * 37) % 256)),
          claimedContentType: 'application/octet-stream',
        ),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.byType(DocumentPreviewWidget), findsNothing);
      expect(find.byType(PdfPreviewWidget), findsNothing);
      expect(find.byType(SandboxedTransactionView), findsOneWidget);
    });

    testWidgets('an oversized transaction says so rather than guessing',
        (tester) async {
      await pump(
        tester,
        ready(bytes: null, claimedContentType: 'image/png', isOversized: true),
      );

      expect(find.byType(Image), findsNothing);
      expect(find.textContaining('too large'), findsOneWidget);
    });
  });
}
