import 'dart:io';

import 'package:ardrive/components/license/cc_type_form.dart';
import 'package:ardrive/models/forms/cc.dart';
import 'package:ardrive/services/license/licenses/cc.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reactive_forms/reactive_forms.dart';

/// The Creative Commons step of a license, in the upload dialog and the
/// license-files dialog.
///
/// It preselected CC0, a public domain dedication, and a license is recorded
/// with the file for good. The uploader now picks one. Its labels were drawn
/// in the disabled colour and hard to read.
void main() {
  /// The real face, so the form lays out at its real width. Loaded here: a
  /// real file read never finishes inside `testWidgets`.
  setUpAll(() async {
    final loader = FontLoader('packages/ardrive_ui/Wavehaus');
    for (final file in Directory('packages/ardrive_ui/assets/fonts')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('Wavehaus'))) {
      final bytes = await file.readAsBytes();
      loader.addFont(
        Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
      );
    }
    await loader.load();
  });

  group('createCcTypeForm', () {
    test('starts with no license chosen', () {
      final form = createCcTypeForm();

      expect(form.control('ccTypeField').value, isNull);
    });

    /// What keeps Next disabled on both dialogs until one is picked.
    test('is not valid until one is chosen', () {
      final form = createCcTypeForm();
      expect(form.valid, isFalse);

      form.control('ccTypeField').value = ccByLicenseMetaV2;
      expect(form.valid, isTrue);
    });
  });

  group('CcTypeForm', () {
    late FormGroup form;

    setUp(() => form = createCcTypeForm());

    Future<ArDriveColorTokens> pumpForm(
      WidgetTester tester, {
      ArDriveThemeData? theme,
    }) async {
      final themeData = theme ?? lightTheme();
      await tester.pumpWidget(
        ArDriveTheme(
          themeData: themeData,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en', '')],
            home: Scaffold(
              body: SizedBox(width: 400, child: CcTypeForm(formGroup: form)),
            ),
          ),
        ),
      );
      return themeData.colorTokens;
    }

    testWidgets('asks for a type and shows none until one is picked',
        (tester) async {
      await pumpForm(tester);

      expect(find.text('Choose a license type'), findsOneWidget);
      expect(find.text(cc0LicenseMeta.name), findsNothing);
      expect(find.text(cc0LicenseMeta.shortName), findsNothing);
    });

    testWidgets('shows the type picked and its short name', (tester) async {
      await pumpForm(tester);

      await tester.tap(find.text('Choose a license type'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(ccByLicenseMetaV2.name).last);
      await tester.pumpAndSettle();

      expect(form.control('ccTypeField').value, ccByLicenseMetaV2);
      expect(find.text(ccByLicenseMetaV2.shortName), findsOneWidget);
      expect(find.text('Choose a license type'), findsNothing);
    });

    for (final (name, theme) in [
      ('light', lightTheme()),
      ('dark', ArDriveThemeData(colorTokens: ArDriveColorTokens.darkMode())),
    ]) {
      testWidgets('draws its words in a readable colour ($name)',
          (tester) async {
        form.control('ccTypeField').value = ccByLicenseMetaV2;
        final tokens = await pumpForm(tester, theme: theme);

        Color colorOf(String text) =>
            tester.widget<Text>(find.text(text)).style!.color!;

        expect(colorOf('Type'), tokens.textMid);
        expect(colorOf(ccByLicenseMetaV2.shortName), tokens.textMid);
      });
    }
  });
}
