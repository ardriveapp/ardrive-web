import 'package:ardrive/components/upload_options.dart';
import 'package:ardrive/pages/drive_detail/components/hover_widget.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The upload dialog's optional settings, behind one line that names only
/// what Upload is waiting on.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    bool? thumbnails = true,
    List<String> summary = const [],
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

  testWidgets('starts closed, with no summary of what is set', (tester) async {
    await pump(tester, compress: true);

    expect(find.text('Options'), findsOneWidget);
    expect(find.textContaining('Thumbnails'), findsNothing);
    expect(find.text('Compressed'), findsNothing);
    expect(find.text('license field'), findsNothing);
    expect(find.text('Upload with thumbnails'), findsNothing);
  });

  testWidgets('names what Upload is waiting on', (tester) async {
    await pump(tester, summary: const ['Choose a license type']);

    expect(find.text('Choose a license type'), findsOneWidget);
  });

  testWidgets('opens to the options, and the summary makes way',
      (tester) async {
    await pump(tester, summary: const ['Choose a license type']);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    expect(find.text('Upload with thumbnails'), findsOneWidget);
    expect(find.text('license field'), findsOneWidget);
    expect(find.text('Choose a license type'), findsNothing);
  });

  testWidgets('the thumbnails box reports the choice', (tester) async {
    bool? changed;
    await pump(tester, onThumbnailsChanged: (value) => changed = value);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Upload with thumbnails'));
    await tester.pump();

    expect(changed, isFalse);
  });

  testWidgets('says what thumbnails cost under the box, not in a hover tip',
      (tester) async {
    await pump(tester, compress: false);
    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    const caption = 'Uses your free upload allowance, then Turbo Credits.';
    expect(find.text(caption), findsOneWidget);
    expect(find.byType(ArDriveIconButton), findsNothing);
    // Lined up with its label, as the compression caption is.
    expect(
        tester.getTopLeft(find.text(caption)).dx,
        closeTo(
            tester.getTopLeft(find.text('Upload with thumbnails')).dx, 0.6));
  });

  testWidgets('says nothing about thumbnails without images', (tester) async {
    await pump(tester, thumbnails: null);

    expect(find.textContaining('Thumbnails'), findsNothing);

    await tester.tap(find.text('Options'));
    await tester.pumpAndSettle();

    expect(find.text('Upload with thumbnails'), findsNothing);
  });

  testWidgets('opens from the keyboard: Tab reaches it, Enter opens',
      (tester) async {
    await pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.text('license field'), findsOneWidget);
  });

  group('Compress text and code', () {
    const label = 'Compress text and code';
    const hint = 'Smaller storage for websites and code.';

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Options'));
      await tester.pumpAndSettle();
    }

    testWidgets('is absent when the review does not offer it', (tester) async {
      await pump(tester, thumbnails: null);
      await open(tester);

      expect(find.text(label), findsNothing);
      expect(find.text(hint), findsNothing);
      expect(find.byType(ArDriveCheckBox), findsNothing);
    });

    testWidgets('is a checkbox with the hint under the label, off',
        (tester) async {
      await pump(tester, thumbnails: null, compress: false);

      await open(tester);

      expect(find.text(label), findsOneWidget);
      expect(find.text(hint), findsOneWidget);
      expect(
          tester.widget<ArDriveCheckBox>(find.byType(ArDriveCheckBox)).checked,
          isFalse);
      // The caption sits under the label and lines up with it, not the box.
      expect(tester.getTopLeft(find.text(hint)).dy,
          greaterThan(tester.getBottomLeft(find.text(label)).dy - 1));
      expect(tester.getTopLeft(find.text(hint)).dx,
          closeTo(tester.getTopLeft(find.text(label)).dx, 0.6));
    });

    testWidgets('has the same box size as the thumbnails checkbox',
        (tester) async {
      await pump(tester, compress: false);
      await open(tester);

      final boxes = tester
          .widgetList<ArDriveCheckBox>(find.byType(ArDriveCheckBox))
          .toList();
      expect(boxes, hasLength(2));
      expect(boxes[0].iconSize, boxes[1].iconSize);
      expect(tester.getTopLeft(find.text('Upload with thumbnails')).dx,
          closeTo(tester.getTopLeft(find.text(label)).dx, 0.6));
    });

    testWidgets('tapping it reports the choice', (tester) async {
      bool? chosen;
      await pump(tester,
          thumbnails: null,
          compress: false,
          onCompressChanged: (value) => chosen = value);
      await open(tester);

      await tester.tap(find.text(label));
      await tester.pump();
      expect(chosen, isTrue);
    });

    testWidgets('is a labelled checkbox to a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester, thumbnails: null, compress: true);
      await open(tester);

      final node = tester.getSemantics(find.byType(ArDriveCheckBox));
      expect(node.label, label);
      expect(node.hasFlag(SemanticsFlag.hasCheckedState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isChecked), isTrue);
      expect(node.hasFlag(SemanticsFlag.isEnabled), isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      handle.dispose();
    });

    testWidgets('Tab reaches it and Space or Enter flips it', (tester) async {
      final chosen = <bool>[];
      await pump(tester,
          thumbnails: null, compress: false, onCompressChanged: chosen.add);
      await open(tester);

      // Tab order: the Options row first, then the checkbox.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(chosen, [true, false]);
    });
  });
}
