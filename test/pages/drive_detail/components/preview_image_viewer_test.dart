import 'package:ardrive/pages/drive_detail/components/preview_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late int next, previous, closed;

  setUp(() {
    next = 0;
    previous = 0;
    closed = 0;
  });

  Future<void> pump(WidgetTester tester,
      {bool hasNext = true, bool hasPrevious = true}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: PreviewImageViewer(
        onNext: hasNext ? () => next++ : null,
        onPrevious: hasPrevious ? () => previous++ : null,
        onClose: () => closed++,
        child: const ColoredBox(color: Colors.blue, child: SizedBox.expand()),
      ),
    ));
  }

  Finder viewer() => find.byType(PreviewImageViewer);
  PreviewImageViewerState state(WidgetTester tester) =>
      tester.state<PreviewImageViewerState>(viewer());

  Future<void> doubleTap(WidgetTester tester) async {
    await tester.tap(viewer());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewer());
    await tester.pumpAndSettle();
  }

  testWidgets('a swipe left is the next photo, right the previous',
      (tester) async {
    await pump(tester);
    await tester.fling(viewer(), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    expect(next, 1);
    await tester.fling(viewer(), const Offset(200, 0), 1000);
    await tester.pumpAndSettle();
    expect(previous, 1);
  });

  testWidgets('a short slow drag springs back and moves nowhere',
      (tester) async {
    await pump(tester);
    await tester.timedDrag(
        viewer(), const Offset(-30, 0), const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(next, 0);
  });

  testWidgets('at the end there is nothing to swipe to', (tester) async {
    await pump(tester, hasNext: false);
    await tester.fling(viewer(), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    expect(next, 0);
    expect(previous, 0);
  });

  testWidgets('a swipe down closes', (tester) async {
    await pump(tester);
    await tester.fling(viewer(), const Offset(0, 250), 1000);
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(next + previous, 0);
  });

  testWidgets('a double tap zooms in, and another zooms out', (tester) async {
    await pump(tester);
    await doubleTap(tester);
    expect(state(tester).isZoomed, isTrue);
    await doubleTap(tester);
    expect(state(tester).isZoomed, isFalse);
  });

  testWidgets('zoomed in, a drag looks around instead of moving on',
      (tester) async {
    await pump(tester);
    await doubleTap(tester);
    await tester.fling(viewer(), const Offset(-200, 0), 1000);
    await tester.pumpAndSettle();
    expect(next, 0);
    expect(state(tester).isZoomed, isTrue);
  });

  testWidgets('a pinch zooms and is never taken for a swipe', (tester) async {
    await pump(tester);
    final center = tester.getCenter(viewer());
    final a = await tester.startGesture(center - const Offset(20, 0));
    final b =
        await tester.startGesture(center + const Offset(20, 0), pointer: 2);
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await a.moveBy(const Offset(-15, 0));
      await b.moveBy(const Offset(15, 0));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(state(tester).isZoomed, isTrue);
    expect(next + previous + closed, 0);
  });
}
