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
                    return Container(
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeBgCanvas,
                      child: Card(
                        margin: const EdgeInsets.all(16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        color: ArDriveTheme.of(context)
                            .themeData
                            .colors
                            .themeBgSurface,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                                margin: EdgeInsets.symmetric(horizontal: 16),
                                height: 84,
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      flex: 2,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 28),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.start,
                                          children: [
                                            const Padding(
                                              padding:
                                                  EdgeInsetsDirectional.only(
                                                      end: 8.0),
                                              child: Icon(Icons.image),
                                            ),
                                            Text('Name'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Flexible(
                                      child: Text(
                                        'Size',
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.start,
                                      ),
                                    ),
                                    Flexible(
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 28),
                                        child: Text(
                                          'Last Updated',
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.start,
                                        ),
                                      ),
                                    ),
                                  ],
                                )),
                            Expanded(
                              child: ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemBuilder: (context, index) {
                                  return Card(
                                    margin: const EdgeInsets.all(8),
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    color: ArDriveTheme.of(context)
                                        .themeData
                                        .colors
                                        .themeBgSubtle,
                                    child: SizedBox(
                                      height: 80,
                                      child: WidgetBookExampleDataTableSource()
                                          .getRow(index),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
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
