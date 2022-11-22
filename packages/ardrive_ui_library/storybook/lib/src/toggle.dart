import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory toggle() {
  return WidgetbookCategory(name: 'Toggle', widgets: [
    WidgetbookComponent(name: 'Toggle', useCases: [
      WidgetbookUseCase(
        name: 'On',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (BuildContext context) {
              return const ArDriveToggle(
                initialState: ToggleState.on,
              );
            },
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Off',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (BuildContext context) {
              return const ArDriveToggle(
                initialState: ToggleState.off,
              );
            },
          );
        },
      ),
      WidgetbookUseCase(
        name: 'disabled',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (BuildContext context) {
              return const ArDriveToggle(
                initialState: ToggleState.disabled,
              );
            },
          );
        },
      )
    ]),
  ]);
}
