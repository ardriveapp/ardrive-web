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
  ]);
}
