import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory button() {
  return WidgetbookCategory(name: 'Button', widgets: [
    WidgetbookComponent(name: 'Button', useCases: [
      WidgetbookUseCase(
        name: 'Primary',
        builder: (context) {
          return Center(
            child: ArDriveButton(
              onPressed: () {
                debugPrint('Primary Button pressed');
              },
              text: 'Add Profile',
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Secundary Light',
        builder: (context) {
          return Center(
            child: ArDriveTheme(
              themeData: lightTheme(),
              child: ArDriveButton(
                style: ArDriveButtonStyle.secondary,
                onPressed: () {
                  debugPrint('Secundary Light Button pressed');
                },
                text: 'Add Profile',
              ),
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Secundary Dark',
        builder: (context) {
          return Center(
            child: ArDriveTheme(
              child: ArDriveButton(
                style: ArDriveButtonStyle.secondary,
                onPressed: () {
                  debugPrint('Secundary Dark Button pressed');
                },
                text: 'Add Profile',
              ),
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Tertiary Dark',
        builder: (context) {
          return Center(
            child: ArDriveTheme(
              child: ArDriveButton(
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
      WidgetbookUseCase(
        name: 'Tertiary Light',
        builder: (context) {
          return Center(
            child: ArDriveTheme(
              themeData: lightTheme(),
              child: ArDriveButton(
                style: ArDriveButtonStyle.tertiary,
                onPressed: () {
                  debugPrint('Tertiary Light Button pressed');
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
