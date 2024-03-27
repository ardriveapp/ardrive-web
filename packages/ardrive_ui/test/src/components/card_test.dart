import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Card widget and its contents render', (tester) async {
    const card = ArDriveCard(
      content: Text('Some widget'),
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: card,
      ),
    ));

    expect(find.byWidget(card), findsOneWidget);
    expect(find.text('Some widget'), findsOneWidget);
  });
}
