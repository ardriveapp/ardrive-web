import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // test if click area renders
  testWidgets('Click Area', (tester) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => ArDriveClickArea(
          child: Container(
            width: 200,
            height: 200,
            color: Colors.red,
          ),
        ),
      ),
    );
    expect(find.byType(ArDriveClickArea), findsOneWidget);
  });
}
