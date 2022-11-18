import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory toggle() {
  return WidgetbookCategory(name: 'Toggle', widgets: [
    WidgetbookComponent(name: 'Toggle', useCases: [
      WidgetbookUseCase(
        name: 'On',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => const ArDriveToggle(
              initialValue: true,
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Off',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => const ArDriveToggle(
              initialValue: false,
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'disabled',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => const ArDriveToggle(
              isEnabled: false,
            ),
          );
        },
      )
    ]),
    WidgetbookComponent(name: 'Toggle Switch', useCases: [
      WidgetbookUseCase(
        name: 'On',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => ArDriveToggleSwitch(
              text: context.knobs.text(label: 'Label'),
              value: true,
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'Off',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => ArDriveToggleSwitch(
              text: context.knobs.text(label: 'Label'),
              value: false,
            ),
          );
        },
      ),
      WidgetbookUseCase(
        name: 'disabled',
        builder: (context) {
          return ArDriveStorybookAppBase(
            builder: (context) => ArDriveToggleSwitch(
              text: context.knobs.text(label: 'Label'),
              isEnabled: false,
            ),
          );
        },
      )
    ]),
  ]);
}
