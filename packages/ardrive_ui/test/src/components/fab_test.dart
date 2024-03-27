import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FAB widget and its contents render', (tester) async {
    const fab = ArDriveFAB(
      child: Icon(Icons.plus_one),
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: fab,
      ),
    ));

    expect(find.byWidget(fab), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('Test if call back is called', (tester) async {
    bool varToChange = false;

    final fab = ArDriveFAB(
      child: const Icon(Icons.plus_one),
      onPressed: () {
        varToChange = true;
      },
    );

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: fab,
      ),
    ));

    await tester.tap(find.bySubtype<FloatingActionButton>());

    expect(find.byWidget(fab), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
    // change the variable
    expect(varToChange, true);
  });
}
