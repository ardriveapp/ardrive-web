import 'package:ardrive/components/upload_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The button that starts an upload says what it uploads.
void main() {
  Future<String> labelFor(WidgetTester tester, int numberOfFiles) async {
    late String label;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Builder(
          builder: (context) {
            label = uploadButtonLabel(context, numberOfFiles);
            return const SizedBox();
          },
        ),
      ),
    );

    return label;
  }

  testWidgets('names the number of files', (tester) async {
    expect(await labelFor(tester, 1), 'Upload 1 file');
    expect(await labelFor(tester, 10), 'Upload 10 files');
  });

  testWidgets('says Upload when there are no files to count', (tester) async {
    expect(await labelFor(tester, 0), 'Upload');
  });
}
