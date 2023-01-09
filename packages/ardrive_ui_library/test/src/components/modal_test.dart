import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Modal widget and its contents render', (tester) async {
    const modal = ArDriveModal(
      content: Text('Some widget'),
      constraints: BoxConstraints(
        maxHeight: 100,
        maxWidth: 100,
      ),
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Some widget'), findsOneWidget);
  });

  testWidgets('ArDriveMiniModal widget and its contents render',
      (tester) async {
    const modal = ArDriveMiniModal(
      content: 'Content',
      title: 'Title',
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('ArDriveIconModal widget and its contents render',
      (tester) async {
    const modal = ArDriveIconModal(
      content: 'Content',
      title: 'Title',
      icon: Icon(Icons.abc),
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.byType(Icon), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('ArDriveLongModal widget and its contents render',
      (tester) async {
    const modal = ArDriveLongModal(
      content: 'Content',
      title: 'Title',
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => const MaterialApp(home: modal),
      ),
    );

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsOneWidget);
  });

  testWidgets('ArDriveStandardModal widget and its contents render',
      (tester) async {
    bool varToChange = false;

    final modal = ArDriveStandardModal(
      content: 'Content',
      title: 'Title',
      actions: [
        ModalAction(
          action: () {
            // just to validate if the callback is calleds
            varToChange = true;
          },
          title: 'Title',
        ),
      ],
    );

    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(home: modal),
      ),
    );

    // taps the action inside the modal
    await tester.tap(find.byType(ArDriveButton));

    expect(find.byWidget(modal), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('Title'), findsNWidgets(2));
    // verify if the variable was changed
    expect(varToChange, true);
  });
}
