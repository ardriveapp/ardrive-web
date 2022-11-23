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
              return Scaffold(
                body: Center(
                  child: ArDriveStandardModal(
                    title: context.knobs.text(
                      label: 'Title',
                      initialValue: 'Warning',
                    ),
                    content: context.knobs.text(
                        label: 'content',
                        initialValue:
                            'The file you have selected is too large to download from the mobile app.'),
                    actions: context.knobs.options(label: 'Actions', options: [
                      const Option(label: 'Zero Actions', value: []),
                      Option(label: 'One Action', value: [
                        ModalAction(
                          action: () {
                            print('action 1');
                          },
                          title: 'Action 1',
                        ),
                      ]),
                      Option(label: 'Two Actions', value: [
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
                      ])
                    ]),
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
                      title: context.knobs.text(
                        label: 'Title',
                        initialValue: 'Warning',
                      ),
                      content: context.knobs.text(
                          label: 'content',
                          initialValue: 'You created a new drive.'),
                      leading:
                          context.knobs.options(label: 'leading', options: [
                        const Option(label: 'No leading', value: null),
                        Option(
                          label: 'With leading',
                          value: ArDriveIcons.uploadCloud(size: 42),
                        )
                      ])),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Long',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              return Scaffold(
                body: Center(
                  child: ArDriveLongModal(
                      title: context.knobs.text(
                        label: 'Title',
                        initialValue: 'Warning',
                      ),
                      content: context.knobs.text(
                        label: 'content',
                        initialValue: 'You created a new drive.',
                      ),
                      action: context.knobs.options(label: 'Action', options: [
                        const Option(label: 'No actions', value: null),
                        Option(
                          label: 'With Action',
                          value: ModalAction(action: () {}, title: 'Action'),
                        )
                      ])),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Modal Icon',
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
                  child: ArDriveIconModal(
                    title: context.knobs
                        .text(label: 'Title', initialValue: 'Settings saved!'),
                    content: context.knobs.text(
                        label: 'Content',
                        initialValue:
                            'Your profile settings have been updated. Now you can go ahead and jump on into the ArDrive app, have some fun, enjoy yourself, and upload some really awesome stuff.'),
                    icon: ArDriveIcons.checkSuccess(
                      size: 88,
                      color: ArDriveTheme.of(context)
                          .themeData
                          .colors
                          .themeSuccessDefault,
                    ),
                    actions: context.knobs.options(label: 'Actions', options: [
                      const Option(label: 'Zero Actions', value: []),
                      Option(label: 'One Action', value: [
                        ModalAction(
                          action: () {
                            print('action 1');
                          },
                          title: 'Action 1',
                        ),
                      ]),
                      Option(label: 'Two Actions', value: [
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
                      ]),
                    ]),
                  ),
                ),
              );
            });
          })
    ])
  ]);
}
