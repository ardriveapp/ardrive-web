import 'dart:io';

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Image widget and its contents render', (tester) async {
    final image = ArDriveImage(image: FileImage(File('test/utils/16.png')));

    await tester.pumpWidget(ArDriveApp(
      builder: (context) => MaterialApp(
        home: image,
      ),
    ));

    expect(find.byWidget(image), findsOneWidget);
  });
}
