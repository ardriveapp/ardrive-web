import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory toggle() {
  return WidgetbookCategory(name: 'Toggle', widgets: [
    WidgetbookComponent(name: 'Toggle Dark', useCases: [
      WidgetbookUseCase(
        name: 'On',
        builder: (context) {
          return const Center(
            child: ArDriveToggle(
              initialState: ToggleState.on,
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Off',
        builder: (context) {
          return const Center(
            child: ArDriveToggle(
              initialState: ToggleState.off,
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'disabled',
        builder: (context) {
          return const Center(
            child: ArDriveToggle(
              initialState: ToggleState.disabled,
            ),
          );
        },
      )
    ]),
    WidgetbookComponent(name: 'Toggle Light', useCases: [
      WidgetbookUseCase(
        name: 'On',
        builder: (context) {
          return Center(
            child: ArDriveTheme(
              themeData: lightTheme(),
              child: const ArDriveToggle(
                initialState: ToggleState.on,
              ),
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Off',
        builder: (context) {
          return Center(
            child: ArDriveTheme(
              themeData: lightTheme(),
              child: const ArDriveToggle(
                initialState: ToggleState.off,
              ),
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'disabled',
        builder: (context) {
          return Center(
              child: ArDriveTheme(
            themeData: lightTheme(),
            child: const ArDriveToggle(
              initialState: ToggleState.disabled,
            ),
          ));
        },
      )
    ])
  ]);
}
