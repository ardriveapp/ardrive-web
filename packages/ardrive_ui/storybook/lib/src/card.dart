import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory card() {
  return WidgetbookCategory(name: 'Card', children: [
    WidgetbookComponent(name: 'Card ', useCases: [
      WidgetbookUseCase(
          name: 'With content',
          builder: (context) {
            return ArDriveStorybookAppBase(
              builder: (context) => _cardWithContent(),
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
