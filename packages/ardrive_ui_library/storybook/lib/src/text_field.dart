import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory textField() {
  return WidgetbookCategory(
    name: 'TextField',
    folders: [
      WidgetbookFolder(name: 'Dark', widgets: [
        WidgetbookComponent(name: 'TextField', useCases: [
          WidgetbookUseCase(
              name: 'Dark',
              builder: (context) {
                return ArDriveTheme(
                    themeData: lightTheme(),
                    child: const Center(
                        child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: ArDriveTextField(),
                    )));
              }),
          WidgetbookUseCase(
              name: 'Light',
              builder: (context) {
                return ArDriveTheme(
                    themeData: lightTheme(),
                    child: const Center(
                        child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: ArDriveTextField(),
                    )));
              })
        ])
      ]),
      WidgetbookFolder(name: 'Light', widgets: [
        WidgetbookComponent(name: 'TextField', useCases: [
          WidgetbookUseCase(
              name: 'Enabled',
              builder: (context) {
                return ArDriveTheme(
                    themeData: lightTheme(),
                    child: const Center(
                        child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: ArDriveTextField(
                        label: 'Enabled',
                        hintText: 'Enabled',
                        isFieldRequired: true,
                      ),
                    )));
              }),
          WidgetbookUseCase(
              name: 'Disabled',
              builder: (context) {
                return ArDriveTheme(
                    themeData: lightTheme(),
                    child: const Center(
                        child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: ArDriveTextField(
                        isEnabled: false,
                        hintText: 'Disabled',
                      ),
                    )));
              }),
          WidgetbookUseCase(
              name: 'Error',
              builder: (context) {
                return ArDriveTheme(
                    themeData: lightTheme(),
                    child: Center(
                        child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ArDriveTextField(
                        hintText: 'Error',
                        validator: (s) => false,
                        errorMessage: 'Error message',
                      ),
                    )));
              }),
          WidgetbookUseCase(
              name: 'Success',
              builder: (context) {
                return ArDriveTheme(
                    themeData: lightTheme(),
                    child: Center(
                        child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ArDriveTextField(
                        hintText: 'Success',
                        validator: (s) => true,
                        successMessage: 'Success MessageEMESSAGEMESSAGEMESSAGE',
                      ),
                    )));
              })
        ]),
      ]),
      WidgetbookFolder(name: 'Dark', widgets: [
        WidgetbookComponent(name: 'TextField', useCases: [
          WidgetbookUseCase(
              name: 'Enabled',
              builder: (context) {
                return ArDriveTheme(
                    child: const Center(
                        child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    label: 'Enabled',
                    hintText: 'Enabled',
                    isFieldRequired: true,
                  ),
                )));
              }),
          WidgetbookUseCase(
              name: 'Disabled',
              builder: (context) {
                return ArDriveTheme(
                    child: const Center(
                        child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    isEnabled: false,
                    hintText: 'Disabled',
                  ),
                )));
              }),
          WidgetbookUseCase(
              name: 'Error',
              builder: (context) {
                return ArDriveTheme(
                    child: Center(
                        child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    hintText: 'Error',
                    validator: (s) => false,
                    errorMessage: 'Error message',
                  ),
                )));
              }),
          WidgetbookUseCase(
              name: 'Success',
              builder: (context) {
                return ArDriveTheme(
                    child: Center(
                        child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ArDriveTextField(
                    hintText: 'Success',
                    validator: (s) => true,
                    successMessage: 'Success MessageEMESSAGEMESSAGEMESSAGE',
                  ),
                )));
              })
        ]),
      ])
    ],
  );
}

WidgetbookCategory loginForm() {
  return WidgetbookCategory(name: 'LoginForm', widgets: [
    WidgetbookComponent(name: 'LoginForm', useCases: [
      WidgetbookUseCase(
          name: 'Dark',
          builder: (context) {
            return Scaffold(
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
            );
          })
    ])
  ]);
}
