import 'package:ardrive/components/upload_options.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    bool? compress,
    void Function(bool)? onCompressChanged,
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
              compress: compress,
              onCompressChanged: onCompressChanged,
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

  testWidgets('opens from the keyboard: Tab reaches it, Enter opens',
      (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(find.text('license field'), findsOneWidget);
  });

  group('Compress text and code', () {
    const label = 'Compress text and code';
    const hint =
        'Smaller storage for websites and code. Other apps may need to unpack these files.';

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Options'));
      await tester.pump();
    }

    testWidgets('is absent when the review does not offer it', (tester) async {
      await pump(tester);
      await open(tester);

      expect(find.text(label), findsNothing);
      expect(find.text(hint), findsNothing);
      expect(find.byType(ArDriveToggleSwitch), findsNothing);
    });

    testWidgets('shows the label, the hint under it and the switch, off',
        (tester) async {
      await pump(tester, compress: false);

      // Closed: nothing about it in the summary while it is off.
      expect(find.text('Compressed'), findsNothing);

      await open(tester);

      expect(find.text(label), findsOneWidget);
      expect(find.text(hint), findsOneWidget);
      final toggle =
          tester.widget<ArDriveToggleSwitch>(find.byType(ArDriveToggleSwitch));
      expect(toggle.value, isFalse);
      expect(toggle.alignRight, isTrue);
      // The hint is a caption under the label, the switch at the row's end.
      expect(tester.getTopLeft(find.text(hint)).dy,
          greaterThan(tester.getBottomLeft(find.text(label)).dy - 1));
      expect(tester.getTopRight(find.byType(ArDriveToggleSwitch)).dx,
          greaterThanOrEqualTo(tester.getTopRight(find.text(hint)).dx - 1));
    });

    testWidgets('tapping it reports the choice, and the summary says so',
        (tester) async {
      bool? chosen;
      await pump(tester,
          compress: false, onCompressChanged: (value) => chosen = value);
      await open(tester);

      await tester.tap(find.text(label));
      // The switch animates, with a timer of its own, for a moment.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(chosen, isTrue);

      await tester.tap(find.text('Options'));
      await tester.pump();
      expect(find.text('Compressed'), findsOneWidget);
    });

    testWidgets('has a label and a toggled state for a screen reader',
        (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, compress: true);
      await open(tester);

      expect(
        tester.getSemantics(find.text(label)),
        matchesSemantics(
          label: label,
          hasToggledState: true,
          isToggled: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('Tab reaches it and Space or Enter flips it', (tester) async {
      final chosen = <bool>[];
      await pump(tester,
          thumbnails: null, compress: false, onCompressChanged: chosen.add);
      await open(tester);

      // Tab order: the Options row first, then the switch.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(chosen, [true, false]);
    });
  });
}
