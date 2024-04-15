import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory submenu() {
  return WidgetbookCategory(name: 'Overlay', children: [
    WidgetbookComponent(
      name: 'submenu',
      useCases: [
        WidgetbookUseCase(
          name: 'submenu',
          builder: (context) {
            return ArDriveStorybookAppBase(
              builder: (context) {
                return ArDriveSubmenu(
                  menuChildren: [
                    ArDriveSubmenuItem(
                      widget: const Text('Create new Drive'),
                    ),
                    ArDriveSubmenuItem(
                      widget: const Text('Create new Drive'),
                      children: [
                        ArDriveSubmenuItem(
                          widget: const Column(
                            children: [
                              Text('Create new Drive'),
                              Divider(),
                            ],
                          ),
                        ),
                        ArDriveSubmenuItem(
                          widget: const Text('Create new Drive'),
                        ),
                        ArDriveSubmenuItem(
                          widget: const Text('Create new Drive'),
                        )
                      ],
                    ),
                    ArDriveSubmenuItem(
                      widget: const Text('Create new Drive'),
                    )
                  ],
                  child: const Text('test'),
                );
              },
            );
          },
        ),
      ],
    ),
  ]);
}
