import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory image() {
  return WidgetbookCategory(name: 'Image', children: [
    WidgetbookComponent(name: 'Image', useCases: [
      WidgetbookUseCase(
        name: 'With SVG Image Provider',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return ArDriveImage(
              image: SvgImage.cachedNetwork(
                'https://jovial.com/images/jupiter.svg',
              ),
            );
          });
        },
      ),
      WidgetbookUseCase(
        name: 'With JPEG Network Image Provider',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return const ArDriveImage(
              image: NetworkImage(
                'https://flutter.github.io/assets-for-api-docs/assets/widgets/owl.jpg',
              ),
            );
          });
        },
      ),
    ]),
  ]);
}
