import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory button() {
  return WidgetbookCategory(name: 'Button', children: [
    WidgetbookComponent(name: 'Button', useCases: [
      WidgetbookUseCase(
        name: 'Primary',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => ArDriveButton(
              onPressed: () {
                debugPrint('Primary Button pressed');
              },
              text: 'Add Profile',
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Secondary',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => ArDriveButton(
              style: ArDriveButtonStyle.secondary,
              onPressed: () {
                debugPrint('Secondary Light Button pressed');
              },
              text: 'Add Profile',
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Tertiary',
        builder: (context) {
          return Center(
            child: ArDriveStorybookAppBase(
              builder: (context) => ArDriveButton(
                style: ArDriveButtonStyle.tertiary,
                onPressed: () {
                  debugPrint('Tertiary Dark Button pressed');
                },
                text: 'Add Profile',
              ),
            ),
          );
        },
      ),
    ])
  ]);
}
