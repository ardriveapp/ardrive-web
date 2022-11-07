import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/colors.dart';
import 'package:widgetbook/widgetbook.dart';

void main() {
  runApp(const StoryBook());
}

class StoryBook extends StatelessWidget {
  const StoryBook({super.key});

  @override
  Widget build(BuildContext context) {
    return Widgetbook.material(
        themes: [WidgetbookTheme(name: 'Theme', data: ThemeData())],
        appInfo: AppInfo(name: 'ArDrive StoryBook'),
        categories: [
          WidgetbookCategory(name: 'Colors', folders: [
            getForegroundColors(),
            getBackgroundColors(),
            getWarningColors(),
            getErrorColors(),
            getInfoColors(),
            getInputColors(),
            getSuccessColors(),
            getOverlayColors(),
          ]),
          WidgetbookCategory(name: 'Toggle', widgets: [
            WidgetbookComponent(name: 'Toggle', useCases: [
              WidgetbookUseCase(
                  name: 'On',
                  builder: (context) {
                    return const Center(
                        child: ArDriveToggle(
                      initialState: ToggleState.on,
                    ));
                  }),
              WidgetbookUseCase(
                  name: 'Off',
                  builder: (context) {
                    return const Center(
                        child: ArDriveToggle(
                      initialState: ToggleState.off,
                    ));
                  }),
              WidgetbookUseCase(
                  name: 'disabled',
                  builder: (context) {
                    return const Center(
                        child: ArDriveToggle(
                      initialState: ToggleState.disabled,
                    ));
                  })
            ])
          ])
        ]);
  }
}
