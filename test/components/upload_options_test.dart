import 'package:ardrive/components/upload_options.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The upload dialog's optional settings, behind one line saying what is set.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool? thumbnails = true,
    List<String> summary = const ['No license'],
    void Function(bool)? onThumbnailsChanged,
  }) async {
    await tester.pumpWidget(
      ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Scaffold(
            body: UploadOptions(
              thumbnails: thumbnails,
              onThumbnailsChanged: onThumbnailsChanged ?? (_) {},
              summary: summary,
              children: const [Text('license field')],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('starts closed, saying what is set', (tester) async {
    await pump(tester);

    expect(find.text('Options'), findsOneWidget);
    expect(find.text('Thumbnails on'), findsOneWidget);
    expect(find.text('No license'), findsOneWidget);
    expect(find.text('license field'), findsNothing);
    expect(find.text('Upload with thumbnails'), findsNothing);
  });

  testWidgets('opens to the options, and the summary makes way',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Options'));
    await tester.pump();

    expect(find.text('Upload with thumbnails'), findsOneWidget);
    expect(find.text('license field'), findsOneWidget);
    expect(find.text('Thumbnails on'), findsNothing);
  });

  testWidgets('the summary follows the thumbnails box', (tester) async {
    bool? changed;
    await pump(tester, onThumbnailsChanged: (value) => changed = value);

    await tester.tap(find.text('Options'));
    await tester.pump();
    await tester.tap(find.text('Upload with thumbnails'));
    await tester.pump();
    await tester.tap(find.text('Options'));
    await tester.pump();

    expect(changed, isFalse);
    expect(find.text('Thumbnails off'), findsOneWidget);
  });

  testWidgets('says nothing about thumbnails without images', (tester) async {
    await pump(tester, thumbnails: null);

    expect(find.textContaining('Thumbnails'), findsNothing);

    await tester.tap(find.text('Options'));
    await tester.pump();

    expect(find.text('Upload with thumbnails'), findsNothing);
  });
}
