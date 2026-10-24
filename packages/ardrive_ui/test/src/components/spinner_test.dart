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
    for (final (size, dimension, stroke) in [
      (ArDriveSpinnerSize.small, 16.0, 2.0),
      (ArDriveSpinnerSize.large, 32.0, 3.0),
    ]) {
      await tester.pumpWidget(wrap(ArDriveSpinner(size: size)));
      expect(
          tester.getSize(find.byType(ArDriveSpinner)), Size.square(dimension));
      expect(
          tester
              .widget<CircularProgressIndicator>(
                  find.byType(CircularProgressIndicator))
              .strokeWidth,
          stroke);
    }
  });

  testWidgets('ArDriveLinearProgress is 4 high and can show progress',
      (tester) async {
    await tester.pumpWidget(wrap(const SizedBox(
      width: 200,
      child: ArDriveLinearProgress(value: 0.25),
    )));

    expect(tester.getSize(find.byType(ArDriveLinearProgress)).height, 4);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0.25);
  });
}
