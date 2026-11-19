import 'dart:convert';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

void main() {
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    Widget wrap(Widget child, {bool reduce = false}) => ArDriveApp(
          themeData: ArDriveThemeData(
            colorTokens: dark
                ? ArDriveColorTokens.darkMode()
                : ArDriveColorTokens.lightMode(),
          ),
          builder: (context) => MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduce),
              child: Scaffold(
                body: Center(
                  child: SizedBox(width: 120, height: 90, child: child),
                ),
              ),
            ),
          ),
        );

    group('ArDriveGalleryTile ($mode)', () {
      testWidgets('skeleton: a plain block, tinted when a colour is given',
          (tester) async {
        await tester.pumpWidget(wrap(const ArDriveGalleryTile(name: 'a.jpg')));
        expect(find.byKey(const ValueKey('gallery-tile-skeleton')),
            findsOneWidget);
        expect(find.byKey(const ValueKey('gallery-tile-image')), findsNothing);
        expect(find.byKey(const ValueKey('gallery-tile-blur')), findsNothing);

        final tokens = ArDriveTheme.of(tester.element(find.byType(Scaffold)))
            .themeData
            .colorTokens;
        ColoredBox box() => tester.widget<ColoredBox>(
            find.byKey(const ValueKey('gallery-tile-skeleton')));
        expect(box().color, tokens.containerL2);

        const tint = Color(0xFF123456);
        await tester.pumpWidget(wrap(const ArDriveGalleryTile(
          name: 'a.jpg',
          placeholderColor: tint,
        )));
        expect(box().color, tint);
      });

      testWidgets(
          'blur-up: the low-res image shows blurred, then the photo '
          'fades in', (tester) async {
        await tester.pumpWidget(wrap(ArDriveGalleryTile(
          name: 'a.jpg',
          lowResImage: MemoryImage(Uint8List.fromList(_png)),
          // Fresh bytes: an image another test decoded would be cached and
          // show on its first frame.
          image: MemoryImage(Uint8List.fromList(_png)),
        )));
        expect(find.byKey(const ValueKey('gallery-tile-blur')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('gallery-tile-image')), findsOneWidget);
        AnimatedOpacity fadeNow() => tester.widget<AnimatedOpacity>(find
            .descendant(
              of: find.byKey(const ValueKey('gallery-tile-image')),
              matching: find.byType(AnimatedOpacity),
            )
            .first);
        expect(fadeNow().opacity, 0);
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
        expect(fadeNow().opacity, 1);
        // Still blurred underneath while it fades.
        expect(find.byKey(const ValueKey('gallery-tile-blur')), findsOneWidget);
        await tester.pump(galleryTileFadeDuration);
        await tester.pump(galleryTileFadeDuration);
        await tester.pump();
        // Done: no blurred layer stays under a loaded tile.
        expect(find.byKey(const ValueKey('gallery-tile-blur')), findsNothing);
        expect(
            find.byKey(const ValueKey('gallery-tile-image')), findsOneWidget);
      });

      testWidgets('reduced motion: no fade, no inset animation',
          (tester) async {
        await tester.pumpWidget(wrap(
          ArDriveGalleryTile(name: 'a.jpg', image: MemoryImage(_png)),
          reduce: true,
        ));
        final animated =
            tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity));
        for (final a in animated) {
          expect(a.duration, Duration.zero);
        }
        expect(
          tester.widget<AnimatedPadding>(find.byType(AnimatedPadding)).duration,
          Duration.zero,
        );
      });

      testWidgets('failed: quiet icon, labelled', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(wrap(const ArDriveGalleryTile(
          name: 'a.jpg',
          failed: true,
          image: null,
        )));
        expect(
            find.byKey(const ValueKey('gallery-tile-failed')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('gallery-tile-skeleton')), findsNothing);
        expect(find.bySemanticsLabel('a.jpg, Could not load'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('an image that cannot be decoded shows failed, and says so',
          (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(wrap(ArDriveGalleryTile(
          name: 'a.jpg',
          image: MemoryImage(Uint8List.fromList([1, 2, 3])),
        )));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(
            find.byKey(const ValueKey('gallery-tile-failed')), findsOneWidget);
        expect(find.bySemanticsLabel('a.jpg, Could not load'), findsOneWidget);
        tester.takeException();
        handle.dispose();
      });

      testWidgets('pending: shows the mark and says so', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(wrap(const ArDriveGalleryTile(
          name: 'a.jpg',
          pending: true,
        )));
        expect(
            find.byKey(const ValueKey('gallery-tile-pending')), findsOneWidget);
        expect(find.bySemanticsLabel('a.jpg, Upload pending'), findsOneWidget);
        handle.dispose();
      });

      testWidgets('selected: insets the photo and ticks', (tester) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(wrap(const ArDriveGalleryTile(name: 'a.jpg')));
        expect(
            find.byKey(const ValueKey('gallery-tile-selected')), findsNothing);
        final before =
            tester.getSize(find.byKey(const ValueKey('gallery-tile-photo')));

        await tester.pumpWidget(wrap(const ArDriveGalleryTile(
          name: 'a.jpg',
          selected: true,
        )));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('gallery-tile-selected')),
            findsOneWidget);
        final after =
            tester.getSize(find.byKey(const ValueKey('gallery-tile-photo')));
        expect(
            after.width, before.width - ArDriveGalleryTile.selectedInset * 2);
        expect(
          tester.getSemantics(find.byType(ArDriveGalleryTile)),
          matchesSemantics(
            label: 'a.jpg',
            isSelected: true,
            isImage: true,
          ),
        );
        handle.dispose();
      });

      testWidgets(
          'a click selects at once; a double-click, touch tap and '
          'Enter open', (tester) async {
        var taps = 0, opens = 0;
        final node = FocusNode();
        await tester.pumpWidget(wrap(ArDriveGalleryTile(
          name: 'a.jpg',
          focusNode: node,
          onTap: () => taps++,
          onOpen: () => opens++,
        )));
        final tile = find.byType(ArDriveGalleryTile);

        // No waiting for the double-tap window.
        await tester.tap(tile, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(taps, 1);
        expect(opens, 0);
        await tester.pump(kDoubleTapTimeout);

        // Two quick clicks: select, then open.
        await tester.tap(tile, kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(tile, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(taps, 2);
        expect(opens, 1);
        await tester.pump(kDoubleTapTimeout);

        // Two slow clicks are two selections.
        await tester.tap(tile, kind: PointerDeviceKind.mouse);
        await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 1));
        await tester.tap(tile, kind: PointerDeviceKind.mouse);
        await tester.pump();
        expect(taps, 4);
        expect(opens, 1);
        await tester.pump(kDoubleTapTimeout);

        // A touch tap opens, as in the list.
        await tester.tap(tile);
        await tester.pump();
        expect(opens, 2);
        expect(taps, 4);

        // The pointer is a hand over the tile.
        expect(
          tester
              .widgetList<MouseRegion>(
                  find.descendant(of: tile, matching: find.byType(MouseRegion)))
              .map((r) => r.cursor),
          contains(SystemMouseCursors.click),
        );

        CustomPaint ring() => tester
            .widgetList<CustomPaint>(find.descendant(
              of: find.byType(ArDriveFocusable),
              matching: find.byType(CustomPaint),
            ))
            .firstWhere((p) => p.foregroundPainter != null,
                orElse: () => const CustomPaint());
        expect(ring().foregroundPainter, isNull);

        // A key press puts the app in keyboard mode; Tab then lands here.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(node.hasFocus, isTrue);
        expect(ring().foregroundPainter, isA<ArDriveFocusRingPainter>());
        // Drawn inside the tile, so a neighbour at a 2 px gap or the edge of
        // the gallery never covers or clips it.
        expect((ring().foregroundPainter! as ArDriveFocusRingPainter).inflate,
            lessThan(0));

        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(opens, 3);
        expect(taps, 4);
        node.dispose();
      });
    });
  }

  group('ArDriveJustifiedGallery', () {
    testWidgets('builds only the rows near the viewport', (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final built = <int>{};
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveJustifiedGallery(
              itemCount: 5000,
              aspectRatioOf: (i) => 1.0 + (i % 3) * 0.2,
              tileBuilder: (context, index, size) {
                built.add(index);
                return SizedBox.expand(key: ValueKey('t$index'));
              },
            ),
          ),
        ),
      ));
      expect(built, isNotEmpty);
      expect(built.length, lessThan(200));
      expect(find.byKey(const ValueKey('t0')), findsOneWidget);
      expect(find.byKey(const ValueKey('t4999')), findsNothing);
    });

    testWidgets('tiles get the laid out size; rows fill the width',
        (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final sizes = <int, Size>{};
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveJustifiedGallery(
              itemCount: 30,
              aspectRatioOf: (_) => 1,
              tileBuilder: (context, index, size) {
                sizes[index] = size;
                return SizedBox.expand(key: ValueKey('t$index'));
              },
            ),
          ),
        ),
      ));
      // 390 wide, 2 px gap, square photos: 4 to a row, ending exactly at 390.
      final h = sizes[0]!.height;
      expect(h, inInclusiveRange(70, 130));
      final rowCount = sizes.entries.where((e) => e.value.height == h).length;
      expect(rowCount, greaterThanOrEqualTo(3));
      final lastInRow = ValueKey('t${rowCount - 1}');
      expect(tester.getTopRight(find.byKey(lastInRow)).dx, 390);
      expect(tester.getTopLeft(find.byKey(const ValueKey('t0'))).dx, 0);
      expect(tester.getSize(find.byKey(const ValueKey('t0'))), sizes[0]);
    });

    testWidgets('tiles are keyed by identity: a swapped item starts clean',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var ids = ['a', 'b', 'c'];
      late StateSetter set;
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(builder: (context, setState) {
              set = setState;
              return ArDriveJustifiedGallery(
                itemCount: ids.length,
                layoutRevision: ids.join(),
                aspectRatioOf: (_) => 1,
                itemKeyOf: (i) => ValueKey(ids[i]),
                tileBuilder: (context, i, size) => ArDriveGalleryTile(
                  name: ids[i],
                  // Only 'a' has its picture.
                  image: ids[i] == 'a' ? MemoryImage(_png) : null,
                ),
              );
            }),
          ),
        ),
      ));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(galleryTileFadeDuration);
      Finder imageIn(String id) => find.descendant(
            of: find.byKey(ValueKey(id)),
            matching: find.byKey(const ValueKey('gallery-tile-image')),
          );
      expect(imageIn('a'), findsOneWidget);

      // 'a' is deleted and 'd' arrives in its place: same index, new file.
      set(() => ids = ['d', 'b', 'c']);
      await tester.pump();
      expect(imageIn('d'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('d')),
          matching: find.byKey(const ValueKey('gallery-tile-skeleton')),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a fractional gap is floored to whole pixels', (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: ArDriveJustifiedGallery(
              itemCount: 12,
              gap: 2.5,
              aspectRatioOf: (_) => 1,
              tileBuilder: (context, i, size) =>
                  SizedBox.expand(key: ValueKey('t$i')),
            ),
          ),
        ),
      ));
      final a = tester.getTopRight(find.byKey(const ValueKey('t0'))).dx;
      final b = tester.getTopLeft(find.byKey(const ValueKey('t1'))).dx;
      expect(b - a, 2);
    });
  });
}
