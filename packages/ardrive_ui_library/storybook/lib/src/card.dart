import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory card() {
  return WidgetbookCategory(name: 'Card', widgets: [
    WidgetbookComponent(name: 'Card Dark', useCases: [
      WidgetbookUseCase(
          name: 'With content',
          builder: (context) {
            return Center(
              child: ArDriveTheme(
                child: _cardWithContent(),
              ),
            );
          }),
    ]),
    WidgetbookComponent(name: 'Card Light', useCases: [
      WidgetbookUseCase(
          name: 'With content',
          builder: (context) {
            return Center(
              child: ArDriveTheme(
                themeData: lightTheme(),
                child: _cardWithContent(),
              ),
            );
          }),
    ]),
  ]);
}
 
Widget _cardWithContent() {
  return ArDriveCard(
    contentPadding: const EdgeInsets.all(16),
    content: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Success',
              style: ArDriveTypography.body.smallBold(),
            ),
            const SizedBox(
              height: 8,
            ),
            Text(
              'You created a new drive',
              style: ArDriveTypography.body.captionRegular(),
            ),
          ],
        ),
        const Icon(Icons.close)
      ],
    ),
  );
}
