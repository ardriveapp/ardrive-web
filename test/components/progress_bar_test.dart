import 'dart:async';

import 'package:ardrive/components/progress_bar.dart';
import 'package:ardrive/sync/domain/sync_progress.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';

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

  testWidgets('a measurable phase draws the bar at its percentage',
      (tester) async {
    await tester.pumpWidget(wrap());
    progress.add(at(0.42));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(LinearPercentIndicator), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      tester
          .widget<LinearPercentIndicator>(find.byType(LinearPercentIndicator))
          .percent,
      0.42,
    );
  });

  testWidgets('a phase that cannot measure itself draws a bar with no value',
      (tester) async {
    await tester.pumpWidget(wrap());
    progress.add(at(0.97, indeterminate: true));
    await tester.pump(const Duration(milliseconds: 10));

    // Indeterminate means value == null: the bar sweeps instead of sitting at
    // a number it has no evidence for.
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, isNull);
    expect(find.byType(LinearPercentIndicator), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
  });

  testWidgets('the bar goes back to a number once the phase can measure again',
      (tester) async {
    await tester.pumpWidget(wrap());
    progress.add(at(0.97, indeterminate: true));
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    progress.add(at(1.0));
    await tester.pump(const Duration(milliseconds: 10));

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(LinearPercentIndicator), findsOneWidget);
  });
}
