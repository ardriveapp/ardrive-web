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
    ])
  ]);
}
