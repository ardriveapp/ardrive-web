import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

    Future<void> pump(
      WidgetTester tester, {
      required int rows,
      Size size = const Size(1440, 900),
      int? rowsPerPage,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bars = 0;
      downloads = 0;
      await tester.pumpWidget(
        ArDriveApp(
          builder: (context) => MaterialApp(
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
                    Text(row.id),
                    const Text('1 B'),
                  ]),
                  rowsPerPage: rowsPerPage,
                  rowsPerPageText: 'Rows per page',
                  headerDivider: true,
                  countOnOnePage: true,
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
                            SizedBox(
                              key: anchor,
                              height: 40,
                              child: Row(
                                children: [
                                  const Expanded(
                                      child: Text('Title', key: _titleKey)),
                                  TextButton(
                                    onPressed: () => downloads++,
                                    child: const Text('Download'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 72),
                          ],
                        ),
                      ),
                      bar: ColoredBox(
                        color: Colors.white,
                        child: Row(
                          children: [
                            const Expanded(child: Text('Bar title')),
                            TextButton(
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
      await tester.tap(find.text('Download'));
      expect(downloads, 1);

      await wheel(tester, 400);
      expect(sliver(tester).progress, 1);
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
  });
}
