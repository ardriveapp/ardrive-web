import 'dart:async';

import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<LinearProgress> progress;

  setUp(() => progress = StreamController<LinearProgress>.broadcast());
  tearDown(() async => progress.close());

  Widget wrap() => MaterialApp(
        home: Scaffold(body: ProgressBar(percentage: progress.stream)),
      );

  SyncProgress at(double value, {bool indeterminate = false}) =>
      SyncProgress.initial().copyWith(
        progress: value,
        isIndeterminate: indeterminate,
      );

  double? drawnValue(WidgetTester tester) => tester
      .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
      .value;

  /// Long enough for the fill to finish travelling to a new value.
  const settle = Duration(milliseconds: 1100);

  testWidgets('a measurable phase draws the bar at its percentage',
      (tester) async {
    await tester.pumpWidget(wrap());
    progress.add(at(0.42));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(settle);

    expect(drawnValue(tester), closeTo(0.42, 0.001));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a phase that cannot measure itself draws a bar with no value',
      (tester) async {
    await tester.pumpWidget(wrap());
    progress.add(at(0.97, indeterminate: true));
    await tester.pump(const Duration(milliseconds: 10));

    // Indeterminate means value == null: the bar sweeps instead of sitting at
    // a number it has no evidence for.
    expect(drawnValue(tester), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the bar goes back to a number once the phase can measure again',
      (tester) async {
    await tester.pumpWidget(wrap());
    progress.add(at(0.97, indeterminate: true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(drawnValue(tester), isNull);

    progress.add(at(1.0));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(settle);

    expect(drawnValue(tester), closeTo(1.0, 0.001));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving an unmeasurable phase never draws less than it showed',
      (tester) async {
    // The regression this bar was rebuilt for. Two widget types used to share
    // this slot - a LinearProgressIndicator while a phase could not measure
    // itself, a LinearPercentIndicator when it could - so `Widget.canUpdate`
    // failed on the swap, Flutter destroyed the element, and percent_indicator
    // built a fresh `Tween(begin: 0.0, end: percent)` in initState and ran it
    // over a second. The bar emptied and refilled: 0.97 -> 0.0 -> 1.0. It fired
    // for anyone with pending transactions, which is anyone who had uploaded
    // recently.
    await tester.pumpWidget(wrap());

    progress.add(at(0.97));
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(settle);

    // One widget type serves both phases, and that is not incidental: two
    // types in this slot is exactly what destroys the element and replays the
    // fill from zero.
    expect(
      find.byType(LinearProgressIndicator),
      findsOneWidget,
      reason: 'a measurable phase must draw the same widget an unmeasurable '
          'one does, or the swap destroys the element',
    );
    expect(drawnValue(tester), closeTo(0.97, 0.001));

    progress.add(at(0.97, indeterminate: true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(drawnValue(tester), isNull,
        reason: 'precondition: the bar is in the unmeasurable phase');

    progress.add(at(1.0));

    // Every frame of the way back, not just where it lands.
    final drawn = <double>[];
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final value = drawnValue(tester);
      if (value != null) {
        drawn.add(value);
      }
    }

    expect(drawn, isNotEmpty);
    expect(
      drawn.where((value) => value < 0.97 - 0.001),
      isEmpty,
      reason: 'the bar must never render below where it already stood: $drawn',
    );
    expect(drawn.last, closeTo(1.0, 0.001));

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the same element draws both phases', (tester) async {
    // The mechanism behind the test above: one widget type in the slot, so
    // there is no unmount to replay an animation from zero.
    await tester.pumpWidget(wrap());

    progress.add(at(0.97));
    await tester.pump(const Duration(milliseconds: 10));
    final before = tester.element(find.byType(LinearProgressIndicator));

    progress.add(at(0.97, indeterminate: true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.element(find.byType(LinearProgressIndicator)), same(before));

    progress.add(at(1.0));
    await tester.pump(const Duration(milliseconds: 10));
    expect(tester.element(find.byType(LinearProgressIndicator)), same(before));

    await tester.pumpWidget(const SizedBox());
  });
}
