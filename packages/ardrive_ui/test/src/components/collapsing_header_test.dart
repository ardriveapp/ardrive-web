import 'package:ardrive_ui/ardrive_ui.dart';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Row extends IndexedItem {
  const _Row(super.index, this.id);

  final String id;

  @override
  List<Object?> get props => [id];
}

/// Records where it is painted: the canvas's own translation, which is what
/// the screen shows, not the render tree's idea of where the box is.
class _Probe extends CustomPainter {
  static double paintedTop = 0;

  @override
  void paint(Canvas canvas, Size size) {
    paintedTop = canvas.getTransform()[13];
  }

  @override
  bool shouldRepaint(_Probe old) => true;
}

const _barHeight = 56.0;
const _headerHeight = 336.0;
const _coverKey = Key('cover');
const _titleKey = Key('title');

void main() {
  group('a table with a collapsing header', () {
    final extent = CollapsingHeaderExtent();
    final anchor = GlobalKey();
    var bars = 0;
    var downloads = 0;
    late FocusNode headerFocus;
    late FocusNode barFocus;

    Future<void> pump(
      WidgetTester tester, {
      required int rows,
      Size size = const Size(1440, 900),
      int? rowsPerPage,
      double textScale = 1,
      bool countOnOnePage = true,
      int? reveal,
      double rowPx = 0,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bars = 0;
      downloads = 0;
      headerFocus = FocusNode();
      barFocus = FocusNode();
      addTearDown(headerFocus.dispose);
      addTearDown(barFocus.dispose);
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: ArDriveDataTable<_Row>(
                  columns: [
                    TableColumn('Name', 1, index: 0),
                    TableColumn('Size', 1, index: 1),
                  ],
                  rows: [for (var i = 0; i < rows; i++) _Row(i, 'row $i')],
                  buildRow: (row) => TableRowWidget([
                    rowPx > 0
                        ? SizedBox(height: rowPx, child: Text(row.id))
                        : Text(row.id),
                    const Text('1 B'),
                  ]),
                  rowsPerPage: rowsPerPage,
                  rowsPerPageText: 'Rows per page',
                  headerDivider: true,
                  countOnOnePage: countOnOnePage,
                  revealRow:
                      reveal == null ? null : _Row(reveal, 'row $reveal'),
                  onChangeMultiSelecting: (_) {},
                  leadingExtent: extent,
                  pinnedInset: _barHeight,
                  leadingSlivers: [
                    SliverCollapsingHeader(
                      barHeight: _barHeight,
                      anchorKey: anchor,
                      extent: extent,
                      header: Padding(
                        padding: const EdgeInsets.only(bottom: 24),
                        child: Column(
                          children: [
                            SizedBox(
                              key: _coverKey,
                              height: 200,
                              child: CustomPaint(painter: _Probe()),
                            ),
                            CollapsingAnchorGate(
                              extent: extent,
                              child: SizedBox(
                                key: anchor,
                                height: 40,
                                child: ColoredBox(
                                  color: const Color(0xFFFF0000),
                                  child: Row(
                                    children: [
                                      const Expanded(
                                          child: Text('Title', key: _titleKey)),
                                      TextButton(
                                        focusNode: headerFocus,
                                        onPressed: () => downloads++,
                                        child: const Text('Download'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 72),
                          ],
                        ),
                      ),
                      bar: ColoredBox(
                        color: const Color(0xFFCCE0FF),
                        child: Row(
                          children: [
                            const Expanded(child: Text('Bar title')),
                            TextButton(
                              focusNode: barFocus,
                              onPressed: () => bars++,
                              child: const Text('Bar download'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    ScrollPosition position(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    RenderSliverCollapsingHeader sliver(WidgetTester tester) =>
        tester.renderObject<RenderSliverCollapsingHeader>(
            find.byType(SliverCollapsingHeader));

    double coverTop(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(_coverKey)).dy;

    Future<void> wheel(WidgetTester tester, double dy) async {
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(const Offset(300, 600)));
      await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
      await tester.pump();
    }

    for (final (name, rows) in [('a short list', 9), ('a long list', 100)]) {
      group('with $name', () {
        testWidgets('the header moves one to one with the wheel, never back',
            (tester) async {
          await pump(tester, rows: rows);
          final top = coverTop(tester);
          expect(sliver(tester).progress, 0);

          var previous = top;
          var previousProgress = 0.0;
          // Past the header and then some, in small steps.
          for (var i = 1; i <= 40; i++) {
            await wheel(tester, 20);
            final offset = position(tester).pixels;
            final now = coverTop(tester);
            // Exactly the offset, so it moves with the content, until the
            // header is gone and the rows go on alone.
            expect(now, moreOrLessEquals(top - offset, epsilon: 0.01));
            // And it is drawn there, not just laid out there.
            if (offset < _headerHeight) {
              expect(_Probe.paintedTop, moreOrLessEquals(now, epsilon: 0.01));
            }
            expect(now, lessThanOrEqualTo(previous));
            expect(sliver(tester).progress,
                greaterThanOrEqualTo(previousProgress));
            previous = now;
            previousProgress = sliver(tester).progress;
          }
          expect(sliver(tester).progress, 1);
          // The headings stay under the bar, the rows go beneath them.
          final headings = tester.getTopLeft(find.text('Name')).dy;
          await wheel(tester, 60);
          expect(tester.getTopLeft(find.text('Name')).dy, headings);
          // And nothing is over them: a row scrolled under is not above.
          expect(find.text('Name').hitTestable(), findsOneWidget);
          expect(
              tester.getTopLeft(find.text('Name')).dy, greaterThan(_barHeight));
        });

        testWidgets('comes back continuously, to everything shown',
            (tester) async {
          await pump(tester, rows: rows);
          final top = coverTop(tester);
          await wheel(tester, 2000);
          expect(sliver(tester).progress, 1);

          var previous = coverTop(tester);
          for (var i = 0; i < 100 && position(tester).pixels > 0; i++) {
            await wheel(tester, -20);
            final now = coverTop(tester);
            expect(now, greaterThanOrEqualTo(previous));
            previous = now;
          }
          expect(position(tester).pixels, 0);
          expect(coverTop(tester), top);
          expect(sliver(tester).progress, 0);
          expect(find.text('Bar title').hitTestable(), findsNothing);
        });

        testWidgets('a fling settles without oscillating', (tester) async {
          await pump(tester, rows: rows);
          final tops = <double>[];
          await tester.fling(
              find.byType(Scrollable).first, const Offset(0, -300), 1500);
          for (var i = 0; i < 90; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            tops.add(coverTop(tester));
          }
          await tester.pumpAndSettle();
          for (var i = 1; i < tops.length; i++) {
            expect(tops[i], lessThanOrEqualTo(tops[i - 1] + 0.001),
                reason: 'frame $i');
          }
          // Settled: nothing moves in the frames after.
          final settled = position(tester).pixels;
          for (var i = 0; i < 30; i++) {
            await tester.pump(const Duration(milliseconds: 16));
            expect(position(tester).pixels, settled);
          }
        });
      });
    }

    testWidgets('a short list scrolls exactly as far as the header collapses',
        (tester) async {
      await pump(tester, rows: 9);
      final header = extent.value;
      expect(header, _headerHeight);
      // Not a pixel more: no range to wobble in, and the table's headings end
      // just under the bar.
      expect(position(tester).maxScrollExtent,
          moreOrLessEquals(header - _barHeight, epsilon: 0.01));
      expect(position(tester).pixels, 0);
      // And the page is at rest: nothing changes without input.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(position(tester).pixels, 0);
        expect(position(tester).maxScrollExtent,
            moreOrLessEquals(header - _barHeight, epsilon: 0.01));
      }
    });

    testWidgets(
        'the bar appears as the title leaves, and is clickable only then',
        (tester) async {
      await pump(tester, rows: 9);
      expect(sliver(tester).progress, 0);
      // The title row's top is 200 down: the bar starts a bar's height
      // before that, and is whole when it arrives.
      await wheel(tester, 100);
      expect(sliver(tester).progress, 0);
      await wheel(tester, 70);
      expect(sliver(tester).progress, inExclusiveRange(0, 1));
      // The header's own button works while the bar is not there.
      await tester.pumpAndSettle();
      await wheel(tester, -200);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Download'));
      expect(downloads, 1);

      await wheel(tester, 400);
      expect(sliver(tester).progress, 1);
      // Reachable from the next frame, which is when focus and pointer are told.
      await tester.pump();
      await tester.tap(find.text('Bar download'));
      expect(bars, 1);
      expect(downloads, 1);
    });

    testWidgets('on a phone, the same', (tester) async {
      await pump(tester, rows: 9, size: const Size(390, 844));
      final top = coverTop(tester);
      var previous = top;
      for (var i = 0; i < 30; i++) {
        await wheel(tester, 15);
        final now = coverTop(tester);
        expect(now, lessThanOrEqualTo(previous));
        previous = now;
      }
      expect(sliver(tester).progress, 1);
      expect(tester.takeException(), isNull);
    });

    Future<Set<FocusNode>> tabThrough(WidgetTester tester) async {
      final reached = <FocusNode>{};
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        for (final node in [headerFocus, barFocus]) {
          if (node.hasPrimaryFocus) reached.add(node);
        }
      }
      return reached;
    }

    testWidgets('Tab at rest reaches the header, never the hidden bar',
        (tester) async {
      await pump(tester, rows: 9);
      final reached = await tabThrough(tester);
      expect(reached, contains(headerFocus));
      expect(reached, isNot(contains(barFocus)));
    });

    testWidgets('Tab once collapsed reaches the bar, never the header',
        (tester) async {
      await pump(tester, rows: 100);
      await wheel(tester, 2000);
      await tester.pump();
      await tester.pump();
      final offset = position(tester).pixels;
      final reached = await tabThrough(tester);
      expect(reached, contains(barFocus));
      expect(reached, isNot(contains(headerFocus)));
      // Focus on the bar does not scroll the page.
      expect(position(tester).pixels, offset);
      barFocus.requestFocus();
      await tester.pump();
      expect(position(tester).pixels, offset);
    });

    testWidgets('a pointer cannot reach the bar before it is in',
        (tester) async {
      await pump(tester, rows: 9);
      expect(find.text('Bar download').hitTestable(), findsNothing);
      await wheel(tester, 2000);
      await tester.pump();
      await tester.pump();
      expect(find.text('Bar download').hitTestable(), findsOneWidget);
    });

    testWidgets(
        'the card ends a radius below the last row without an indicator',
        (tester) async {
      await pump(tester, rows: 9, countOnOnePage: false);
      await wheel(tester, 2000);
      final last = tester.getRect(find.text('row 8'));
      final end = find.byWidgetPredicate((w) =>
          w is ConstrainedBox &&
          w.constraints.minHeight == cardDefaultBorderRadius &&
          w.constraints.maxHeight == double.infinity);
      expect(end, findsOneWidget);
      expect(tester.getSize(end).height,
          greaterThanOrEqualTo(cardDefaultBorderRadius));
      expect(tester.getTopLeft(end).dy, greaterThan(last.center.dy));
    });

    for (final scale in [1.5, 2.0]) {
      testWidgets('the headings hold their text at ${scale}x', (tester) async {
        await pump(tester, rows: 30, textScale: scale);
        await wheel(tester, 2000);
        await tester.pump();
        expect(tester.takeException(), isNull);
        final name = tester.getRect(find.text('Name'));
        // The row is as tall as the text at this size, not squeezed to a
        // fixed height.
        expect(name.height, greaterThan(24));
        // Under the bar, in its own row, and nothing over it.
        expect(name.top, greaterThanOrEqualTo(_barHeight + 14));
        expect(find.text('Name').hitTestable(), findsOneWidget);
        // The hairline under the headings is below the text, whatever its size.
        final hairline = find.byWidgetPredicate((w) =>
            w is Container &&
            w.constraints?.maxHeight == 1 &&
            w.constraints?.minHeight == 1);
        expect(hairline, findsOneWidget);
        expect(tester.getTopLeft(hairline).dy,
            greaterThanOrEqualTo(name.bottom - 0.5));
        // The rows start below it: scrolled to the top of the first one, the
        // first row's text is under the whole of the headings' row.
        await wheel(tester, -2000);
        await wheel(tester, 2000);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }

    for (final index in [0, 10, 24]) {
      testWidgets('a revealed row ($index) ends below the bar and headings',
          (tester) async {
        await pump(tester, rows: 100, rowsPerPage: 25, reveal: index);
        await tester.pumpAndSettle();
        final row = tester.getRect(
            find.byType(ArDriveClickArea).evaluate().isEmpty
                ? find.byKey(ValueKey(_Row(index, 'row $index')))
                : find.byWidgetPredicate((w) =>
                    w is ArDriveClickArea &&
                    w.key == ValueKey(_Row(index, 'row $index'))));
        expect(row.top, greaterThanOrEqualTo(_barHeight + 45));
        expect(row.bottom, lessThanOrEqualTo(900));
      });
    }

    /// The window's pixel at [x], [y].
    Future<Color> pixel(WidgetTester tester, int x, int y) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      final image = await tester.runAsync(boundary.toImage);
      final data = (await tester.runAsync(
          () => image!.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      final i = (y * image!.width + x) * 4;
      return Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      );
    }

    testWidgets('the title row is never drawn under the bar as it comes in',
        (tester) async {
      await pump(tester, rows: 9);
      // At rest the title row (red) is there, 200 down.
      expect((await pixel(tester, 300, 220)).red, 255);
      expect((await pixel(tester, 300, 220)).green, 0);

      var wasPartial = false;
      // Every step of the hand-over, a pixel at a time.
      for (var i = 0; i < 40; i++) {
        await wheel(tester, 5);
        final progress = sliver(tester).progress;
        final top = tester.getTopLeft(find.byKey(const Key('title'))).dy;
        // A column through the title row, under the bar's bottom edge and
        // away from the text.
        final y = (top + 8).round();
        // Strictly one after the other: while any of the header's row is
        // showing, nothing of the bar is drawn.
        final inBarZone = await pixel(tester, 300, 20);
        if (progress < 0.4) {
          expect(inBarZone.red, 255,
              reason: 'the bar is drawn at progress $progress');
          expect(sliver(tester).barProgress, 0);
        }
        if (y < 56 * sliver(tester).barProgress + 2 || y >= 900) continue;
        final c = await pixel(tester, 700, y);
        if (progress >= 0.4) {
          expect(c.green, greaterThan(200),
              reason: 'the row shows at progress $progress, y $y');
        } else if (progress > 0.05) {
          // Half way out: neither the full row nor nothing.
          if (c.green > 20 && c.green < 235) wasPartial = true;
        }
      }
      expect(wasPartial, isTrue);
    });

    for (final at in [0.45, 0.6]) {
      testWidgets('the faded title row is no target at progress $at',
          (tester) async {
        await pump(tester, rows: 9);
        // The header's Download, where it is at rest.
        final spot = tester.getCenter(find.text('Download'));
        while (sliver(tester).progress < at) {
          await wheel(tester, 2);
        }
        await tester.pump();
        await tester.pump();
        expect(find.text('Download').hitTestable(), findsNothing);
        await tester.tap(find.text('Download'), warnIfMissed: false);
        await tester.pump();
        expect(downloads, 0);
        // And Tab never lands on it.
        final reached = await tabThrough(tester);
        expect(reached, isNot(contains(headerFocus)));
        expect(spot, isNotNull);
      });
    }

    testWidgets(
        'scrolling a row into view stops exactly under the bar and headings',
        (tester) async {
      await pump(tester, rows: 25);
      await wheel(tester, 6000);
      await tester.pump();
      // A row that is partly under the headings, brought to the top.
      final rows = [
        for (var i = 0; i < 25; i++)
          if (find.text('row $i').evaluate().isNotEmpty) i
      ];
      final hidden = rows.firstWhere(
          (i) => tester.getTopLeft(find.text('row $i')).dy < _barHeight + 45);
      Scrollable.ensureVisible(
        tester.element(find.byWidgetPredicate((w) =>
            w is ArDriveClickArea &&
            w.key == ValueKey(_Row(hidden, 'row $hidden')))),
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
      );
      await tester.pumpAndSettle();
      final top = tester
          .getRect(find.byWidgetPredicate((w) =>
              w is ArDriveClickArea &&
              w.key == ValueKey(_Row(hidden, 'row $hidden'))))
          .top;
      // To the pixel: the row's top is the headings' last line, and the
      // headings start at the bar's bottom. No gap and no overlap.
      final hairline = find.byWidgetPredicate((w) =>
          w is Container &&
          w.constraints?.maxHeight == 1 &&
          w.constraints?.minHeight == 1);
      expect(top, tester.getRect(hairline).bottom);
      // The headings pinned right under the bar: 14 above their row, 6 below.
      expect(tester.getTopLeft(find.text('Name')).dy,
          greaterThanOrEqualTo(_barHeight + 14));
      expect(
          tester.getRect(hairline).top -
              tester.getTopLeft(find.text('Name')).dy,
          lessThan(40));
    });

    testWidgets('a revealed row far down a list of tall rows is found',
        (tester) async {
      await pump(tester, rows: 100, rowsPerPage: 100, reveal: 99, rowPx: 100);
      await tester.pumpAndSettle();
      final row = tester.getRect(find.byWidgetPredicate((w) =>
          w is ArDriveClickArea && w.key == const ValueKey(_Row(99, 'row 99'))));
      expect(row.top, greaterThanOrEqualTo(_barHeight + 45));
      expect(row.bottom, lessThanOrEqualTo(900));
    });
  });
}
