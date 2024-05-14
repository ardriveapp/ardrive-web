import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory toggle() {
  return WidgetbookCategory(name: 'Toggle', children: [
    WidgetbookComponent(name: 'Toggle Switch', useCases: [
      WidgetbookUseCase(
        name: 'Toggle',
        builder: (context) {
          return ArDriveStorybookAppBase(
              key: const ValueKey('Toggle'),
              builder: (context) {
                final isEnabled = context.knobs
                    .boolean(label: 'IsEnabled', initialValue: true);
                final value = context.knobs
                    .boolean(label: 'IsChecked', initialValue: true);
                return ArDriveToggleSwitch(
                  key: ValueKey('$isEnabled$value'),
                  isEnabled: isEnabled,
                  text:
                      context.knobs.text(label: 'Label', initialValue: 'Label'),
                  value: value,
                );
              });
        },
      ),
    ]),
  ]);
}
