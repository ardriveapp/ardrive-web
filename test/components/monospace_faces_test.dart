import 'package:ardrive/blocs/note_create/note_create_state.dart';
import 'package:ardrive/components/markdown_style_sheet.dart';
import 'package:ardrive/components/note_create/note_editor_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Code, text files and the note editor are set in Roboto Mono. They named
/// Courier New before, which never loaded, so they were Wavehaus.
void main() {
  group('Markdown code', () {
    for (final isFullScreen in [true, false]) {
      test('is monospace ${isFullScreen ? 'full screen' : 'in the card'}', () {
        final sheet = arDriveMarkdownStyleSheet(
          ArDriveTypographyNew.desktop,
          ArDriveColorTokens.darkMode(),
          isFullScreen: isFullScreen,
        );

        expect(sheet.code!.fontFamily, ArDriveMonospace.family);
        expect(sheet.code!.fontFamilyFallback, ArDriveMonospace.fallback);
      });
    }
  });

  // They were a full paragraphNormal style, a size above the card's text.
  test('bold and italic keep the size of the text around them', () {
    final sheet = arDriveMarkdownStyleSheet(
      ArDriveTypographyNew.desktop,
      ArDriveColorTokens.darkMode(),
      isFullScreen: false,
    );

    expect(sheet.strong!.fontSize, isNull);
    expect(sheet.em!.fontSize, isNull);
  });

  testWidgets('the note editor writes in the monospace face', (tester) async {
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: SizedBox(
              height: 400,
              child: NoteEditorWidget(
                initialContent: '# Title',
                onChanged: (_) {},
                viewMode: NoteViewMode.editOnly,
                onViewModeChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.style!.fontFamily, ArDriveMonospace.family);
  });
}
