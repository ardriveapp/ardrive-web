import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/utils/data_table_source.dart';
import 'package:widgetbook/widgetbook.dart';

import 'colors.dart';

class StoryBook extends StatelessWidget {
  const StoryBook({super.key});

  @override
  Widget build(BuildContext context) {
    return ArDriveApp(
      builder: (context) => Widgetbook(
        devices: const [
          Device.desktop(
            name: 'Web Browser',
            resolution: Resolution(
              nativeSize: DeviceSize(width: 1920, height: 1080),
              scaleFactor: 2,
            ),
          ),
          Device.mobile(
            name: 'Smartphone',
            resolution: Resolution(
              nativeSize: DeviceSize(width: 1080, height: 1920),
              scaleFactor: 2,
            ),
          )
        ],
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
          getTypographyCategory(true),
          getTypographyCategory(false),
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
            name: 'Button',
            widgets: [
              WidgetbookComponent(
                name: 'Button',
                useCases: [
                  WidgetbookUseCase(
                    name: 'Primary',
                    builder: (context) {
                      return Center(
                        child: ArDriveButton(
                          onPressed: () {
                            debugPrint('Primary Button pressed');
                          },
                          text: 'Add Profile',
                        ),
                      );
                    },
                  ),
                  WidgetbookUseCase(
                    name: 'Secondary Light',
                    builder: (context) {
                      return Center(
                        child: ArDriveTheme(
                          themeData: lightTheme(),
                          child: ArDriveButton(
                            style: ArDriveButtonStyle.secondary,
                            onPressed: () {
                              debugPrint('Secondary Light Button pressed');
                            },
                            text: 'Add Profile',
                          ),
                        ),
                      );
                    },
                  ),
                  WidgetbookUseCase(
                    name: 'Secondary Dark',
                    builder: (context) {
                      return Center(
                        child: ArDriveTheme(
                          child: ArDriveButton(
                            style: ArDriveButtonStyle.secondary,
                            onPressed: () {
                              debugPrint('Secondary Dark Button pressed');
                            },
                            text: 'Add Profile',
                          ),
                        ),
                      );
                    },
                  ),
                  WidgetbookUseCase(
                    name: 'Tertiary Dark',
                    builder: (context) {
                      return Center(
                        child: ArDriveTheme(
                          child: ArDriveButton(
                            style: ArDriveButtonStyle.tertiary,
                            onPressed: () {
                              debugPrint('Tertiary Dark Button pressed');
                            },
                            text: 'Add Profile',
                          ),
                        ),
                      );
                    },
                  ),
                  WidgetbookUseCase(
                    name: 'Tertiary Light',
                    builder: (context) {
                      return Center(
                        child: ArDriveTheme(
                          themeData: lightTheme(),
                          child: ArDriveButton(
                            style: ArDriveButtonStyle.tertiary,
                            onPressed: () {
                              debugPrint('Tertiary Light Button pressed');
                            },
                            text: 'Add Profile',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          WidgetbookCategory(name: 'Data Table', widgets: [
            WidgetbookComponent(
              name: 'Paginated Data Table',
              useCases: [
                WidgetbookUseCase(
                  name: 'Sample Data Table',
                  builder: (context) {
                    return ArDriveDataTable(
                      rows: WidgetBookExampleDataTableSource().getRows(),
                      columns: const [
                        Text('Name'),
                        Text('Size'),
                        Text('Last Updated'),
                      ],
                    );
                  },
                ),
              ],
            )
          ])
        ],
      ),
    );
  }
}
