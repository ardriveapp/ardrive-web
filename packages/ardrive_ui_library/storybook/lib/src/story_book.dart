import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/text_field.dart';
import 'package:storybook/src/toggle.dart';
import 'package:widgetbook/widgetbook.dart';

import 'colors.dart';

class StoryBook extends StatelessWidget {
  const StoryBook({super.key});

  @override
  Widget build(BuildContext context) {
    return ArDriveApp(
      builder: (context) => Widgetbook.material(
          themes: [
            WidgetbookTheme(
              name: 'Dark',
              data: darkMaterialTheme(),
            ),
            WidgetbookTheme(
              name: 'Light',
              data: lightMaterialTheme(),
            ),
          ],
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
            toggle(),
            textField(),
            loginForm(),
          ]),
    );
  }
}
