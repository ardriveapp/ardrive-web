import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory checkBox() {
  return WidgetbookCategory(name: 'Check Box', widgets: [
    WidgetbookComponent(name: 'Check Box', useCases: [
      WidgetbookUseCase(
        name: 'Check Box',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final isEnabled =
                context.knobs.boolean(label: 'IsEnabled', initialValue: true);
            final isIndeterminate = context.knobs
                .boolean(label: 'isIndeterminate', initialValue: false);
            final value =
                context.knobs.boolean(label: 'IsChecked', initialValue: true);
            return ArDriveCheckBox(
              title: context.knobs.text(label: 'Title', initialValue: 'Normal'),
              checked: value,
              isDisabled: !isEnabled,
              isIndeterminate: isIndeterminate,
              key: ValueKey('$isEnabled$value$isIndeterminate'),
            );
          });
        },
      ),
    ]),
  ]);
}
