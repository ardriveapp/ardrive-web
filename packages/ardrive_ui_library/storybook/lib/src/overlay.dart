import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory overlay() {
  final controller = ArDriveOverlayController();
  return WidgetbookCategory(name: 'Overlay', widgets: [
    WidgetbookComponent(name: 'Overlay', useCases: [
      WidgetbookUseCase(
        name: 'Overlay',
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
                  controller: controller,
                  child: ArDriveButton(
                      text: 'Show overlay',
                      onPressed: () {
                        if (controller.isShowing) {
                          controller.hide();
                        } else {
                          controller.show();
                        }
                      }),
                )
              ],
            );
          });
        },
      ),
    ]),
  ]);
}
