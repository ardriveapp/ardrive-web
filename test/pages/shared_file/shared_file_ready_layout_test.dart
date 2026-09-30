import 'package:ardrive/pages/shared_file/shared_file_ready_layout.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_view.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ready card both the share page and `/view` are built from.
///
/// Each page tests what it puts in the card; this tests the card itself - the
/// arrangement both pages now get by construction.
void main() {
  const identity = Key('identity');
  const download = Key('download');
  const inlinePreview = Key('inlinePreview');
  const paneContent = Key('paneContent');
  const pane = Key('pane');
  const panel = Key('panel');
  const notice = Key('notice');
  const note = Key('note');

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
        home: Material(
          child: SingleChildScrollView(
            child: Center(child: SizedBox(width: 1040, child: child)),
          ),
        ),
      ),
    );
  }

  late List<double?> panelHeights;

  SharedFileReadyLayout layout({required bool isWide, bool preview = true}) {
    return SharedFileReadyLayout(
      isWide: isWide,
      notices: const [SizedBox(key: notice, height: 10)],
      identity: const SizedBox(key: identity, width: 200, height: 40),
      download: const SizedBox(key: download, width: 120, height: 40),
      belowHeader: const [SizedBox(key: note, height: 10)],
      inlinePreview:
          preview ? const SizedBox(key: inlinePreview, height: 100) : null,
      previewPaneKey: pane,
      previewPane: const SizedBox(key: paneContent, width: 50, height: 50),
      infoPanel: (height) {
        panelHeights.add(height);
        return SizedBox(key: panel, height: height ?? 80);
      },
    );
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(1440, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(wrap(child));
  }

  setUp(() => panelHeights = []);

  group('the phone column', () {
    testWidgets('reads top to bottom: notice, name, Download, preview, details',
        (tester) async {
      await pump(tester, layout(isWide: false));

      double top(Key key) => tester.getRect(find.byKey(key)).top;

      expect(top(notice), lessThan(top(identity)));
      expect(top(identity), lessThan(top(download)));
      expect(top(download), lessThan(top(note)));
      expect(top(note), lessThan(top(inlinePreview)));
      expect(top(inlinePreview), lessThan(top(panel)));

      // No pane, and a panel that sizes to its content.
      expect(find.byKey(pane), findsNothing);
      expect(find.byKey(paneContent), findsNothing);
      expect(panelHeights, [null]);
    });

    testWidgets('has no resting box when there is nothing to preview',
        (tester) async {
      await pump(tester, layout(isWide: false, preview: false));

      expect(find.byKey(inlinePreview), findsNothing);
      expect(find.byKey(panel), findsOneWidget);
    });
  });

  group('the desktop card', () {
    testWidgets('puts Download beside the name, above the pane',
        (tester) async {
      await pump(tester, layout(isWide: true));

      final name = tester.getRect(find.byKey(identity));
      final button = tester.getRect(find.byKey(download));
      final box = tester.getRect(find.byKey(pane));

      expect(button.left, greaterThan(name.left));
      expect(button.center.dy, closeTo(name.center.dy, 1));
      expect(button.bottom, lessThan(box.top));
      expect(tester.getRect(find.byKey(notice)).bottom,
          lessThanOrEqualTo(name.top));
    });

    testWidgets('lays the pane out at a fixed height, with the panel beside it',
        (tester) async {
      await pump(tester, layout(isWide: true));

      final box = tester.getRect(find.byKey(pane));
      final details = tester.getRect(find.byKey(panel));

      expect(box.height, SharedFileReadyLayout.previewPaneHeight);
      expect(details.left, greaterThan(box.right));
      expect(details.top, box.top);
      // The panel is asked to hold the pane's height, so the two line up.
      expect(panelHeights, [SharedFileReadyLayout.previewPaneHeight]);
    });

    testWidgets('centres what is in the pane, and shows no inline preview',
        (tester) async {
      await pump(tester, layout(isWide: true));

      final box = tester.getRect(find.byKey(pane));
      final content = tester.getRect(find.byKey(paneContent));

      expect(content.center.dx, closeTo(box.center.dx, 1));
      expect(content.center.dy, closeTo(box.center.dy, 1));
      expect(find.byKey(inlinePreview), findsNothing);
    });
  });

  group('the info panel', () {
    testWidgets('offers the history as a second tab, and asks for it once',
        (tester) async {
      var opened = 0;

      await pump(
        tester,
        SharedFileInfoPanel(
          details: const Text('the details'),
          versions: const Text('the versions'),
          onVersionsOpened: () => opened++,
        ),
      );

      expect(find.text('the details'), findsOneWidget);
      expect(find.text('Version history'), findsOneWidget);

      await tester.tap(find.text('Version history'));
      await tester.pump();
      expect(find.text('the versions'), findsOneWidget);

      await tester.tap(find.text('File details'));
      await tester.pump();
      await tester.tap(find.text('Version history'));
      await tester.pump();

      // Each visit to the tab asks; the resolver is what remembers.
      expect(opened, 2);
    });

    testWidgets('is the details alone for something with no history',
        (tester) async {
      await pump(
        tester,
        const SharedFileInfoPanel(details: Text('the details')),
      );

      expect(find.text('File details'), findsOneWidget);
      expect(find.text('Version history'), findsNothing);
      expect(find.text('the details'), findsOneWidget);

      await tester.tap(find.text('File details'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('the details'), findsOneWidget);
    });

    testWidgets('holds a fixed height, scrolling what does not fit',
        (tester) async {
      await pump(
        tester,
        const SharedFileInfoPanel(
          height: 200,
          details: SizedBox(height: 900, child: Text('long details')),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(find.byType(SharedFileInfoPanel)).height,
        200,
      );
    });
  });
}
