import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory dropArea() {
  return WidgetbookCategory(name: 'DropArea', children: [
    WidgetbookComponent(name: 'DropArea', useCases: [
      WidgetbookUseCase(
        name: 'DropArea',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return ArDriveDropAreaSingleInput(
              controller: ArDriveDropAreaSingleInputController(
                onDragEntered: () {},
                onDragExited: () {},
                onError: (e) {},
                onFileAdded: (file) {},
              ),
              errorDescription: context.knobs.text(
                label: 'Error description',
                initialValue: 'Something went wrong!',
              ),
              height: context.knobs
                  .number(label: 'height', initialValue: 204)
                  .toDouble(),
              width: context.knobs
                  .number(label: 'width', initialValue: 552)
                  .toDouble(),
              dragAndDropButtonTitle: context.knobs.text(
                label: 'Drag and drop button title',
                initialValue: 'Drag & Drop your File',
              ),
              dragAndDropDescription: context.knobs.text(
                label: 'Drag and drop description',
                initialValue: 'Browse to Upload',
              ),
            );
          });
        },
      ),
    ]),
  ]);
}
