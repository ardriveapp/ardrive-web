import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory progressBar() {
  return WidgetbookCategory(name: 'Progress Bar', children: [
    WidgetbookComponent(name: 'Progress Bar', useCases: [
      WidgetbookUseCase(
        name: 'Progress Bar',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            final percentage = context.knobs
                .slider(label: 'Progress', initialValue: 0.5, max: 1, min: 0);
            return ArDriveProgressBar(
              percentage: percentage,
            );
          });
        },
      ),
    ]),
  ]);
}
