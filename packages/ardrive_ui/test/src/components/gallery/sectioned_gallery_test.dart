import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ArDriveGalleryGeometry geometry(
  List<int> counts, {
  double width = 400,
  double ratio = 1,
  double rowHeight = 100,
}) =>
    ArDriveGalleryGeometry.compute(
      sections: [
        for (var i = 0; i < counts.length; i++)
          ArDriveGallerySection(
            key: 's$i',
            itemCount: counts[i],
            header: const SizedBox(),
          ),
      ],
      aspectRatioOf: (_) => ratio,
      width: width,
      defaultRowHeight: rowHeight,
      defaultGap: 4,
    );

void main() {
  group('ArDriveGalleryGeometry', () {
    test('numbers items across sections and records each section\'s top', () {
      final g = geometry([5, 3]);
      expect(g.itemCount, 8);
      expect(g.sectionOffsets.first, 0);
      expect(g.sectionOffsets[1], greaterThan(galleryHeaderHeight));
      // Every item sits in exactly one row.
      final seen = [for (final r in g.rows) ...r.items.map((i) => i.index)];
      expect(seen, [0, 1, 2, 3, 4, 5, 6, 7]);
      // The second section's first row starts after its header.
      final first = g.rows.firstWhere((r) => r.section == 1);
      expect(first.top, g.sectionOffsets[1] + galleryHeaderHeight);
    });

    test('left and right follow the order across a section edge', () {
      final g = geometry([2, 2]);
      expect(g.neighbour(0, GalleryDirection.left), isNull);
      expect(g.neighbour(1, GalleryDirection.right), 2);
      expect(g.neighbour(2, GalleryDirection.left), 1);
      expect(g.neighbour(3, GalleryDirection.right), isNull);
    });

    test('up and down stay as near the same place across as they can', () {
      // 400 px wide, square tiles of about 100 px: four to a row.
      final g = geometry([10]);
      expect(g.rows.first.items.length, greaterThan(2));
      final perRow = g.rows.first.items.length;
      // Directly below.
      expect(g.neighbour(1, GalleryDirection.down), perRow + 1);
      expect(g.neighbour(perRow + 1, GalleryDirection.up), 1);
      // Nothing above the first row or below the last.
      expect(g.neighbour(0, GalleryDirection.up), isNull);
      expect(g.neighbour(9, GalleryDirection.down), isNull);
    });

    test('down from a short last row lands on the nearest tile below', () {
      final g = geometry([5, 6]);
      // Row 0 of section 0 is full (4), its second row holds one tile (4),
      // and going down from it crosses into the next month's first row.
      final lastOfFirstSection = g.rowOf(4)!;
      final below = g.neighbour(4, GalleryDirection.down)!;
      expect(g.rows[g.rowOf(below)!].section, 1);
      expect(g.rowOf(below), lastOfFirstSection + 1);
    });

    test('sectionAt finds the month an offset is in', () {
      final g = geometry([8, 8, 8]);
      expect(g.sectionAt(0), 0);
      expect(g.sectionAt(g.sectionOffsets[1]), 1);
      expect(g.sectionAt(g.sectionOffsets[2] + 10), 2);
    });
  });

  group('ArDriveSectionedGallery', () {
    Widget app(
      ArDriveSectionedGalleryController controller,
      List<int> counts, {
      double width = 400,
      double height = 300,
    }) =>
        ArDriveApp(
          builder: (context) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Stack(children: [
                    Positioned.fill(
                      child: ArDriveSectionedGallery(
                        controller: controller,
                        targetRowHeight: 100,
                        sections: [
                          for (var i = 0; i < counts.length; i++)
                            ArDriveGallerySection(
                              key: 's$i',
                              itemCount: counts[i],
                              header: Text('Month $i'),
                            ),
                        ],
                        aspectRatioOf: (_) => 1,
                        tileBuilder: (context, index, size) =>
                            Text('tile $index'),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      right: 0,
                      child: ArDriveGalleryScrubber(
                        controller: controller,
                        semanticLabel: 'Timeline',
                        entries: [
                          for (var i = 0; i < counts.length; i++)
                            ArDriveGalleryScrubberEntry(
                              section: i,
                              title: 'Month $i',
                              tick: '${2020 + i}',
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        );

    testWidgets('builds only the rows near the screen and reports geometry',
        (tester) async {
      final controller = ArDriveSectionedGalleryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller, [40, 40, 40]));
      await tester.pump();

      expect(find.byKey(const ValueKey('gallery-header-s0')), findsOneWidget);
      expect(find.text('tile 0'), findsOneWidget);
      // Far below: not built.
      expect(find.text('tile 100'), findsNothing);
      expect(controller.geometry!.itemCount, 120);
    });

    testWidgets('jumpToSection scrolls a month\'s header to the top',
        (tester) async {
      final controller = ArDriveSectionedGalleryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller, [40, 40, 40]));
      await tester.pump();

      controller.jumpToSection(2);
      await tester.pump();
      expect(find.byKey(const ValueKey('gallery-header-s2')), findsOneWidget);
      expect(controller.scroll.offset,
          closeTo(controller.geometry!.sectionOffsets[2], 1));
    });

    testWidgets('ensureVisible scrolls just enough to show a tile\'s row',
        (tester) async {
      final controller = ArDriveSectionedGalleryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller, [40, 40]));
      await tester.pump();

      controller.ensureVisible(30);
      await tester.pump();
      expect(find.text('tile 30'), findsOneWidget);
    });

    testWidgets(
        'the list knows its whole height before it is scrolled, so the '
        'last tile is one jump away', (tester) async {
      final controller = ArDriveSectionedGalleryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller, [3, 1, 2, 1, 600]));
      await tester.pump();

      final g = controller.geometry!;
      final last = g.lines.last;
      final position = controller.scroll.position;
      expect(
        position.maxScrollExtent,
        closeTo(last.top + last.extent - position.viewportDimension, 1),
      );

      controller.ensureVisible(g.itemCount - 1);
      await tester.pump();
      expect(find.text('tile ${g.itemCount - 1}'), findsOneWidget);
    });

    testWidgets('the timeline is for a long folder only', (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final short = ArDriveSectionedGalleryController();
      addTearDown(short.dispose);
      await tester.pumpWidget(app(short, [3]));
      await tester.pump();
      await tester.pump();
      expect(
          find.byKey(const ValueKey('gallery-scrubber-thumb')), findsNothing);

      final long = ArDriveSectionedGalleryController();
      addTearDown(long.dispose);
      await tester.pumpWidget(app(long, [60, 60, 60]));
      await tester.pump();
      await tester.pump();
      expect(
          find.byKey(const ValueKey('gallery-scrubber-thumb')), findsOneWidget);
      // Year ticks at rest on a wide screen.
      expect(find.text('2020'), findsOneWidget);
    });

    testWidgets(
        'dragging the timeline jumps through the folder and names '
        'the month', (tester) async {
      tester.view.physicalSize = const Size(1000, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = ArDriveSectionedGalleryController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(app(controller, [60, 60, 60]));
      await tester.pump();
      await tester.pump();

      final track = tester.getRect(find.byType(ArDriveGalleryScrubber));
      final gesture = await tester.startGesture(
        Offset(track.center.dx, track.top + 2),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(Offset(track.center.dx, track.center.dy));
      await gesture.moveTo(Offset(track.center.dx, track.bottom - 1));
      await tester.pump();
      // Near the end of the content: the last month.
      expect(controller.scroll.offset,
          closeTo(controller.geometry!.contentHeight - 300, 200));
      final bubble = tester.widget<AnimatedOpacity>(
          find.byKey(const ValueKey('gallery-scrubber-bubble')));
      expect(bubble.opacity, 1);
      expect(find.text('Month 2'), findsWidgets);
      await gesture.up();
      await tester.pump();
    });
  });
}
