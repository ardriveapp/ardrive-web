import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ArDriveDropAreaSingleInput widget and its contents render',
      (tester) async {
    final dropArea = ArDriveDropAreaSingleInput(
      controller: ArDriveDropAreaSingleInputController(
        onDragEntered: () {},
        onDragExited: () {},
        onError: (e) {},
        onFileAdded: (file) {},
      ),
      dragAndDropButtonTitle: '',
      dragAndDropDescription: '',
    );
    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: dropArea,
      ),
    ));

    expect(find.byWidget(dropArea), findsOneWidget);
  });
}
