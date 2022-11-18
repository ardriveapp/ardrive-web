import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory textField() {
  return WidgetbookCategory(
    name: 'TextField',
    widgets: [
      WidgetbookComponent(name: 'TextField', useCases: [
        WidgetbookUseCase(
            name: 'Enabled',
            builder: (context) {
              return ArDriveStorybookAppBase(
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    label: context.knobs.text(label: 'Label'),
                    hintText: context.knobs.text(label: 'Hint text'),
                    isFieldRequired: true,
                  ),
                ),
              );
            }),
        WidgetbookUseCase(
            name: 'Disabled',
            builder: (context) {
              return ArDriveStorybookAppBase(
                builder: (context) => const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    isEnabled: false,
                    hintText: 'Disabled',
                  ),
                ),
              );
            }),
        WidgetbookUseCase(
            name: 'Error',
            builder: (context) {
              return ArDriveStorybookAppBase(
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    label: context.knobs.text(label: 'Label'),
                    hintText: context.knobs.text(label: 'Hint text'),
                    validator: (s) => false,
                    errorMessage: context.knobs.text(label: 'Error message'),
                  ),
                ),
              );
            }),
        WidgetbookUseCase(
            name: 'Success',
            builder: (context) {
              return ArDriveStorybookAppBase(builder: (context) {
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    label: context.knobs.text(label: 'Label'),
                    hintText: context.knobs.text(label: 'Hint text'),
                    validator: (s) => true,
                    successMessage:
                        context.knobs.text(label: 'Success message'),
                  ),
                );
              });
            }),
      ]),
      WidgetbookComponent(name: 'LoginForm', useCases: [
        WidgetbookUseCase(
            name: 'Login form',
            builder: (context) {
              return ArDriveStorybookAppBase(
                builder: (context) => Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Welcome Back',
                            style: ArDriveTypography.headline.headline4Bold(),
                          ),
                          const SizedBox(
                            height: 32,
                          ),
                          const ArDriveTextField(
                            hintText: 'Enter Username',
                          ),
                          const SizedBox(
                            height: 16,
                          ),
                          const ArDriveTextField(
                            hintText: 'Enter Password',
                          ),
                        ]),
                  ),
                ),
              );
            })
      ])
    ],
  );
}

WidgetbookCategory loginForm() {
  return WidgetbookCategory(name: 'LoginForm', widgets: []);
}
