import 'package:ardrive/pages/drive_detail/components/document_preview_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(
          body: SizedBox(width: 480, height: 600, child: child),
        ),
      ),
    );
  }

  const notes = DocumentPreviewWidget(
    filename: 'notes.txt',
    content: 'one\ntwo',
    contentType: 'text/plain',
    isSharePage: false,
  );

  testWidgets('plain text is in the text colour', (tester) async {
    await tester.pumpWidget(wrap(notes));

    // It had no colour of its own.
    final style = tester.widget<Text>(find.text('one\ntwo')).style!;
    expect(style.color, ArDriveColorTokens.lightMode().textHigh);
  });

  // A text file's columns and indentation line up only in a monospace face.
  testWidgets('plain text is in the monospace face', (tester) async {
    await tester.pumpWidget(wrap(notes));

    final style = tester.widget<Text>(find.text('one\ntwo')).style!;
    expect(style.fontFamily, ArDriveMonospace.family);
    expect(style.fontFamilyFallback, ArDriveMonospace.fallback);
  });

  testWidgets('the controls are named in the reader\'s language',
      (tester) async {
    await tester.pumpWidget(wrap(notes));

    expect(find.byTooltip('Copy text'), findsOneWidget);
    expect(find.byTooltip('Expand'), findsOneWidget);
  });

  group('Copy text', () {
    Future<void> copyWith(WidgetTester tester, {required bool refused}) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData' && refused) {
            throw PlatformException(code: 'denied');
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(wrap(notes));
      await tester.tap(find.byTooltip('Copy text'));
      await tester.pump();
    }

    testWidgets('says it copied', (tester) async {
      await copyWith(tester, refused: false);

      expect(find.text('Copied!'), findsOneWidget);
    });

    // It said "Copied to clipboard" whether or not anything was.
    testWidgets('says so when the browser refuses', (tester) async {
      await copyWith(tester, refused: true);

      expect(find.text("Couldn't copy"), findsOneWidget);
      expect(find.text('Copied!'), findsNothing);
    });
  });
}
