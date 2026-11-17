import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap(Widget child) => ArDriveApp(
        builder: (context) => MaterialApp(
          home: Scaffold(body: Center(child: child)),
        ),
      );

  testWidgets('ArDriveSpinner comes in two sizes', (tester) async {
    for (final (size, dimension) in [
      (ArDriveSpinnerSize.small, 16.0),
      (ArDriveSpinnerSize.large, 32.0),
    ]) {
      await tester.pumpWidget(wrap(ArDriveSpinner(size: size)));
      expect(
          tester.getSize(find.byType(ArDriveSpinner)), Size.square(dimension));
    }
  });

  testWidgets('ArDriveSpinner is a full arc from the first frame',
      (tester) async {
    await tester.pumpWidget(wrap(const ArDriveSpinner()));
    // Not Material's indeterminate ring, which starts as a dot and grows.
    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, 0.75);
  });

  testWidgets('ArDriveSpinner can go spinning, measured, spinning again',
      (tester) async {
    for (final value in [null, 0.5, null]) {
      await tester.pumpWidget(wrap(ArDriveSpinner(value: value)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        0.75);
  });

  testWidgets('ArDriveSpinner shows a measured value as given', (tester) async {
    await tester.pumpWidget(wrap(const ArDriveSpinner(value: 0.4)));
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        0.4);
  });

  testWidgets('ArDriveLinearProgress is 4 high and can show progress',
      (tester) async {
    await tester.pumpWidget(wrap(const SizedBox(
      width: 200,
      child: ArDriveLinearProgress(value: 0.25),
    )));
    // The fill walks to a new value.
    await tester.pumpAndSettle();

    expect(tester.getSize(find.byType(ArDriveLinearProgress)).height, 4);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.25);
  });

  testWidgets('ArDriveLinearProgress never falls back after an unknown spell',
      (tester) async {
    Future<void> show(double? value) => tester.pumpWidget(wrap(SizedBox(
          width: 200,
          child: ArDriveLinearProgress(value: value),
        )));
    double? drawn() => tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
        .value;

    await show(0.8);
    await tester.pumpAndSettle();
    await show(null);
    await tester.pump(const Duration(milliseconds: 500));
    expect(drawn(), isNull);

    await show(1.0);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 40));
      expect(drawn(), greaterThanOrEqualTo(0.8));
    }
  });
}
