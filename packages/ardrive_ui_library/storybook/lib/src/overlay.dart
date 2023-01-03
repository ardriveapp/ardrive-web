import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory overlay() {
  return WidgetbookCategory(name: 'Overlay', widgets: [
    WidgetbookComponent(name: 'Dropdown', useCases: [
      WidgetbookUseCase(
        name: 'Dropdown',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return Column(
              children: [
                ArDriveDropdown(
                    items: [
                      ArDriveDropdownItem(
                        content: Text(
                          'Create new Drive',
                          style: ArDriveTypography.body.buttonLargeBold(),
                        ),
                      ),
                      ArDriveDropdownItem(
                        content: Text(
                          'Create new Drive',
                          style: ArDriveTypography.body.buttonLargeBold(),
                        ),
                      ),
                      ArDriveDropdownItem(
                        content: Text(
                          'Create new Drive',
                          style: ArDriveTypography.body.buttonLargeBold(),
                        ),
                      )
                    ],
                    child: Container(
                      child: Text('some text'),
                    ))
              ],
            );
          });
        },
      ),
    ]),
  ]);
}
