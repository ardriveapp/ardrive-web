import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory fab() {
  return WidgetbookCategory(name: 'FAB', children: [
    WidgetbookComponent(name: 'FAB', useCases: [
      WidgetbookUseCase(
        name: 'Primary',
        builder: (context) {
          return Center(
            child: ArDriveFAB(
              child: const Icon(Icons.plus_one),
              onPressed: () {
                debugPrint('Primary FAB pressed');
              },
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Secondary',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => ArDriveFAB(
              foregroundColor: Colors.black,
              backgroundColor: Colors.white,
              child: const Icon(Icons.plus_one),
              onPressed: () {
                debugPrint('Secondary FAB pressed');
              },
            ),
          );
        },
      ),
    ])
  ]);
}
