import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory tabView() {
  return WidgetbookCategory(name: 'Tab View', children: [
    WidgetbookComponent(name: 'Tab Bar', useCases: [
      WidgetbookUseCase(
        name: 'Tab Bar',
        builder: (context) {
          return ArDriveStorybookAppBase(builder: (context) {
            return const ArDriveTabView(
              tabs: [
                ArDriveTab(
                  Tab(child: Text('One')),
                  Center(child: Text('One')),
                ),
                ArDriveTab(
                  Tab(child: Text('Two')),
                  Center(child: Text('Two')),
                ),
                ArDriveTab(
                  Tab(child: Text('Three')),
                  Center(child: Text('Three')),
                ),
                ArDriveTab(
                  Tab(child: Text('Four')),
                  Center(child: Text('Four')),
                )
              ],
            );
          });
        },
      ),
    ]),
  ]);
}
