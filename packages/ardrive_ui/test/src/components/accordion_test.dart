import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Accordion renders', (tester) async {
    final accordion = ArDriveAccordion(
      children: [
        ArDriveAccordionItem(
          const ListTile(
            title: Text('Accordion Title'),
          ),
          [
            ListTile(
              title: const Text('Subtitle'),
              subtitle: const Text('Subtitle Lorem Ipsum'),
              onTap: () {},
            )
          ],
        )
      ],
    );
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => Material(
          child: MaterialApp(
            home: accordion,
          ),
        ),
      ),
    );

    expect(find.byWidget(accordion), findsOneWidget);
    expect(find.text('Accordion Title'), findsOneWidget);
    // verify if the second list tile shows
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
