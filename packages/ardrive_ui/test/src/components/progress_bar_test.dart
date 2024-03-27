import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Card widget and its contents render', (tester) async {
    const progressBar = ArDriveProgressBar(
      percentage: 0.1,
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: progressBar,
      ),
    ));

    expect(find.byWidget(progressBar), findsOneWidget);
  });
}
