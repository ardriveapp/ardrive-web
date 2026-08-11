import 'dart:typed_data';

import 'package:ardrive/pages/drive_detail/components/pdf_preview_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// What a viewer that cannot render is allowed to leave on screen.
///
/// The rasteriser itself is not exercised here - it needs pdf.js or a platform
/// renderer, neither of which exists in a VM test - so the viewer is injected.
/// What is being held down is the promise around it: a PDF that will not render
/// degrades to something the recipient can still use, never to a broken pane.
void main() {
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
        home: Scaffold(body: child),
      ),
    );
  }

  final bytes = Uint8List.fromList([37, 80, 68, 70]);

  testWidgets('renders the inline viewer when there are bytes to render',
      (tester) async {
    await tester.pumpWidget(wrap(
      PdfPreviewWidget(
        filename: 'Q3 Report.pdf',
        previewUrl: 'https://gateway.example/data-tx',
        pdfBytes: bytes,
        canOpenOnGateway: true,
        viewerBuilder: (context, bytes, onRenderFailed) =>
            const Text('rasterised pages'),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('rasterised pages'), findsOneWidget);
    expect(find.text('Open PDF'), findsNothing);
  });

  testWidgets('a render failure degrades to the open-in-a-new-tab affordance',
      (tester) async {
    await tester.pumpWidget(wrap(
      PdfPreviewWidget(
        filename: 'Q3 Report.pdf',
        previewUrl: 'https://gateway.example/data-tx',
        pdfBytes: bytes,
        canOpenOnGateway: true,
        viewerBuilder: (context, bytes, onRenderFailed) {
          // A real viewer reports its failure once it has tried; this one
          // reports it as soon as the frame it was built in is done.
          WidgetsBinding.instance.addPostFrameCallback((_) => onRenderFailed());

          return const Text('rasterised pages');
        },
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('rasterised pages'), findsNothing);
    expect(find.text('Open PDF'), findsOneWidget);
    expect(
      find.textContaining('Opens in a new tab'),
      findsOneWidget,
    );
    expect(find.text('Q3 Report.pdf'), findsOneWidget);
  });

  testWidgets('a public PDF with no bytes offers the gateway straight away',
      (tester) async {
    await tester.pumpWidget(wrap(
      const PdfPreviewWidget(
        filename: 'Q3 Report.pdf',
        previewUrl: 'https://gateway.example/data-tx',
        canOpenOnGateway: true,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Open PDF'), findsOneWidget);
  });

  testWidgets('a private PDF that will not render offers nothing to open',
      (tester) async {
    await tester.pumpWidget(wrap(
      PdfPreviewWidget(
        filename: 'Q3 Report.pdf',
        previewUrl: 'https://gateway.example/data-tx',
        pdfBytes: bytes,
        viewerBuilder: (context, bytes, onRenderFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onRenderFailed());

          return const Text('rasterised pages');
        },
      ),
    ));
    await tester.pumpAndSettle();

    // A gateway holds only this file's ciphertext, so there is no honest link
    // to offer - and the card says so rather than pretending.
    expect(find.text('Open PDF'), findsNothing);
    expect(find.text('Preview unavailable'), findsOneWidget);
  });
}
