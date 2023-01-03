import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ArDriveDropAreaSingleInput widget and its contents render',
      (tester) async {
    const dropArea = ArDriveDropAreaSingleInput(
      dragAndDropButtonTitle: '',
      dragAndDropDescription: '',
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => const MaterialApp(
        home: dropArea,
      ),
    ));

    expect(find.byWidget(dropArea), findsOneWidget);
  });
}
