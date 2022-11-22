import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:storybook/src/ardrive_app_base.dart';
import 'package:storybook/utils/data_table_source.dart';
import 'package:widgetbook/widgetbook.dart';

WidgetbookCategory dataTable() {
  return WidgetbookCategory(name: 'DataTable', widgets: [
    WidgetbookComponent(name: 'DataTable ', useCases: [
      WidgetbookUseCase(
          name: 'With content',
          builder: (context) {
            return ArDriveStorybookAppBase(
              builder: (context) => _dataTableWithContent(),
            );
          }),
    ]),
  ]);
}

Widget _dataTableWithContent() {
  return ArDriveDataTable(
    rows: WidgetBookExampleDataTableSource().getRows(),
    columns: const [
      Text('Name'),
      Text('Size'),
      Text('Last Updated'),
    ],
  );
}
