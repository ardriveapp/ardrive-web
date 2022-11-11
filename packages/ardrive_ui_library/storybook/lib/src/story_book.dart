import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
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
            WidgetbookCategory(name: 'Toggle', widgets: [
              WidgetbookComponent(name: 'Toggle Dark', useCases: [
                WidgetbookUseCase(
                  name: 'On',
                  builder: (context) {
                    return const Center(
                      child: ArDriveToggle(
                        initialState: ToggleState.on,
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'Off',
                  builder: (context) {
                    return const Center(
                      child: ArDriveToggle(
                        initialState: ToggleState.off,
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'disabled',
                  builder: (context) {
                    return const Center(
                      child: ArDriveToggle(
                        initialState: ToggleState.disabled,
                      ),
                    );
                  },
                )
              ]),
              WidgetbookComponent(name: 'Toggle Light', useCases: [
                WidgetbookUseCase(
                  name: 'On',
                  builder: (context) {
                    return Center(
                      child: ArDriveTheme(
                        themeData: lightTheme(),
                        child: const ArDriveToggle(
                          initialState: ToggleState.on,
                        ),
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'Off',
                  builder: (context) {
                    return Center(
                      child: ArDriveTheme(
                        themeData: lightTheme(),
                        child: const ArDriveToggle(
                          initialState: ToggleState.off,
                        ),
                      ),
                    );
                  },
                ),
                WidgetbookUseCase(
                  name: 'disabled',
                  builder: (context) {
                    return Center(
                        child: ArDriveTheme(
                      themeData: lightTheme(),
                      child: const ArDriveToggle(
                        initialState: ToggleState.disabled,
                      ),
                    ));
                  },
                )
              ])
            ]),
            WidgetbookCategory(
              name: 'TextField',
              folders: [
                WidgetbookFolder(name: 'Dark', widgets: [
                  WidgetbookComponent(name: 'TextField', useCases: [
                    WidgetbookUseCase(
                        name: 'Dark',
                        builder: (context) {
                          return ArDriveTheme(
                              themeData: lightTheme(),
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ArDriveTextField(),
                              )));
                        }),
                    WidgetbookUseCase(
                        name: 'Light',
                        builder: (context) {
                          return ArDriveTheme(
                              themeData: lightTheme(),
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ArDriveTextField(),
                              )));
                        })
                  ])
                ]),
                WidgetbookFolder(name: 'Light', widgets: [
                  WidgetbookComponent(name: 'TextField', useCases: [
                    WidgetbookUseCase(
                        name: 'Enabled',
                        builder: (context) {
                          return ArDriveTheme(
                              themeData: lightTheme(),
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ArDriveTextField(
                                  hintText: 'Enabled',
                                ),
                              )));
                        }),
                    WidgetbookUseCase(
                        name: 'Disabled',
                        builder: (context) {
                          return ArDriveTheme(
                              themeData: lightTheme(),
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ArDriveTextField(
                                  isEnabled: false,
                                  hintText: 'Disabled',
                                ),
                              )));
                        }),
                    WidgetbookUseCase(
                        name: 'Error',
                        builder: (context) {
                          return ArDriveTheme(
                              themeData: lightTheme(),
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ArDriveTextField(
                                  hintText: 'Error',
                                  validator: (s) => s,
                                ),
                              )));
                        }),
                    WidgetbookUseCase(
                        name: 'Success',
                        builder: (context) {
                          return ArDriveTheme(
                              themeData: lightTheme(),
                              child: Center(
                                  child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: ArDriveTextField(
                                  hintText: 'Success',
                                  validator: (s) => null,
                                ),
                              )));
                        })
                  ])
                ])
              ],
            ),
            WidgetbookCategory(name: 'LoginForm', widgets: [
              WidgetbookComponent(name: 'LoginForm', useCases: [
                WidgetbookUseCase(
                    name: 'Dark',
                    builder: (context) {
                      return Scaffold(
                        body: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Welcome Back',
                                  style: ArDriveTypography.headline
                                      .headline4Bold(),
                                ),
                                SizedBox(
                                  height: 32,
                                ),
                                ArDriveTextField(
                                  hintText: 'Enter Username',
                                ),
                                SizedBox(
                                  height: 16,
                                ),
                                ArDriveTextField(
                                  hintText: 'Enter Password',
                                ),
                              ]),
                        ),
                      );
                    })
              ])
            ])
          ]),
    );
  }
}
