import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory modals() {
  return WidgetbookCategory(name: 'Modals', widgets: [
    WidgetbookComponent(name: 'Modals', useCases: [
      WidgetbookUseCase(
          name: 'Standard',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final actions = [
                ModalAction(
                  action: () {
                    print('action 1');
                  },
                  title: 'Action 1',
                ),
                ModalAction(
                  action: () {
                    print('action 2');
                  },
                  title: 'Action 2',
                ),
              ];
              return Scaffold(
                body: Center(
                  child: ArDriveStandardModal(
                    content:
                        'The file you have selected is too large to download from the mobile app.',
                    title: 'Warning',
                    actions: actions,
                  ),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Mini',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              return Scaffold(
                body: Center(
                  child: ArDriveMiniModal(
                    content: 'You created a new drive.',
                    title: 'Warning',
                    leading: ArDriveIcons.uploadCloud(size: 42),
                  ),
                ),
              );
            });
          })
    ])
  ]);
}
