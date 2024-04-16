// ignore_for_file: avoid_print

import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory modals() {
  return WidgetbookCategory(name: 'Modals', children: [
    WidgetbookComponent(name: 'Modals', useCases: [
      WidgetbookUseCase(
          name: 'Standard',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final modal = ArDriveStandardModal(
                title: context.knobs.text(
                  label: 'Title',
                  initialValue: 'Warning',
                ),
                description: context.knobs.text(
                    label: 'content',
                    initialValue:
                        'The file you have selected is too large to download from the mobile app.'),
                actions: context.knobs.options(
                    label: 'Actions',
                    labelBuilder: (option) => option!.isEmpty
                        ? 'None'
                        : option.length == 1
                            ? 'One'
                            : option.length == 2
                                ? 'Two'
                                : 'Three',
                    options: [
                      [],
                      [
                        ModalAction(
                          action: () {
                            print('action 1');
                          },
                          title: 'Action 1',
                        ),
                      ],
                      [
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
                      ],
                      [
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
                        ModalAction(
                          action: () {
                            print('action 3');
                          },
                          title: 'Action 3',
                        ),
                      ]
                    ]),
              );
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      modal,
                      const SizedBox(
                        height: 16,
                      ),
                      ArDriveButton(
                        text: 'Open modal',
                        onPressed: () {
                          showAnimatedDialog(context, content: modal);
                        },
                      )
                    ],
                  ),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Mini',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final modal = ArDriveMiniModal(
                title: context.knobs.text(
                  label: 'Title',
                  initialValue: 'Warning',
                ),
                content: context.knobs.text(
                    label: 'content', initialValue: 'You created a new drive.'),
                leading: context.knobs.options(
                  label: 'leading',
                  labelBuilder: (value) => value == null ? 'null' : 'Icon',
                  options: [
                    null,
                    const ArDriveIcon(
                      icon: ArDriveIconsData.triangle,
                      color: Colors.red,
                    ),
                  ],
                ),
              );
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      modal,
                      const SizedBox(
                        height: 16,
                      ),
                      ArDriveButton(
                        text: 'Open modal',
                        onPressed: () {
                          showAnimatedDialog(context, content: modal);
                        },
                      )
                    ],
                  ),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Long',
          builder: (context) {
            return ArDriveStorybookAppBase(builder: (context) {
              final modal = ArDriveLongModal(
                  title: context.knobs.text(
                    label: 'Title',
                    initialValue: 'Warning',
                  ),
                  content: context.knobs.text(
                    label: 'content',
                    initialValue: 'You created a new drive.',
                  ),
                  action: context.knobs.options(label: 'Action', options: [
                    null,
                    ModalAction(action: () {}, title: 'Action'),
                  ]));

              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      modal,
                      const SizedBox(
                        height: 16,
                      ),
                      ArDriveButton(
                        text: 'Open modal',
                        onPressed: () {
                          showAnimatedDialog(context, content: modal);
                        },
                      )
                    ],
                  ),
                ),
              );
            });
          }),
      WidgetbookUseCase(
          name: 'Modal Icon',
          builder: (context) {
            final modal = ArDriveIconModal(
              title: context.knobs
                  .text(label: 'Title', initialValue: 'Settings saved!'),
              content: context.knobs.text(
                  label: 'Content',
                  initialValue:
                      'Your profile settings have been updated. Now you can go ahead and jump on into the ArDrive app, have some fun, enjoy yourself, and upload some really awesome stuff.'),
              icon: ArDriveIcon(
                icon: ArDriveIconsData.check_cirle,
                size: 88,
                color: ArDriveTheme.of(context)
                    .themeData
                    .colors
                    .themeSuccessDefault,
              ),
              actions: context.knobs.options(label: 'Actions', options: [
                [],
                [
                  ModalAction(
                    action: () {
                      print('action 1');
                    },
                    title: 'Action 1',
                  ),
                ],
                [
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
                ],
              ]),
            );
            return ArDriveStorybookAppBase(builder: (context) {
              return Scaffold(
                body: Center(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    modal,
                    const SizedBox(
                      height: 16,
                    ),
                    ArDriveButton(
                      text: 'Open modal',
                      onPressed: () {
                        showAnimatedDialog(context, content: modal);
                      },
                    )
                  ],
                )),
              );
            });
          })
    ])
  ]);
}
