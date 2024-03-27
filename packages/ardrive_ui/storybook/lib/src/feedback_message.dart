import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory feedbackMessage() {
  return WidgetbookCategory(name: 'Feedback Message', children: [
    WidgetbookComponent(name: 'Feedback Message', useCases: [
      WidgetbookUseCase(
        name: 'Feedback Message',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return const FeedbackMessage(
              text: 'This is a feedback message',
            );
          });
        },
      ),
    ]),
  ]);
}
