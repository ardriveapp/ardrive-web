import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory tabView() {
  return WidgetbookCategory(name: 'Tab View', widgets: [
    WidgetbookComponent(name: 'Tab Bar', useCases: [
      WidgetbookUseCase(
        name: 'Tab Bar',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return const ArDriveTabView(
              tabs: [
                Tab(
                  child: Text('One'),
                ),
                Tab(
                  child: Text('Two'),
                ),
                Tab(
                  child: Text('Three'),
                ),
              ],
              children: [
                Center(
                  child: Text('One'),
                ),
                Center(
                  child: Text('Two'),
                ),
                Center(
                  child: Text('Three'),
                ),
              ],
            );
          });
        },
      ),
    ]),
  ]);
}
