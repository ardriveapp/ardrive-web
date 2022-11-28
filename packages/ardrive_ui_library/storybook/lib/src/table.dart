import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:flutter/material.dart';
import 'package:widgetbook/widgetbook.dart';

import 'ardrive_app_base.dart';

WidgetbookCategory table() {
  return WidgetbookCategory(name: 'Table', widgets: [
    WidgetbookComponent(name: 'Table ', useCases: [
      WidgetbookUseCase(
          name: 'With content',
          builder: (context) {
            return ArDriveStorybookAppBase(
              builder: (context) => Scaffold(
                  body: Padding(
                padding: const EdgeInsets.all(40.0),
                child: _tableWithContent(context),
              )),
            );
          }),
    ]),
  ]);
}

Widget _tableWithContent(BuildContext context) {
  final space1 =
      context.knobs.number(label: 'Space 1 column', initialValue: 3).toInt();
  final space2 =
      context.knobs.number(label: 'Space 2 column', initialValue: 1).toInt();
  final space3 =
      context.knobs.number(label: 'Space 3 column', initialValue: 1).toInt();
  return ArDriveTable<List<String>>(
    leading: context.knobs.boolean(label: 'With leading')
        ? (row) {
            return const Icon(Icons.folder_copy);
          }
        : null,
    trailing: context.knobs.boolean(label: 'With trailing')
        ? (row) => const Icon(Icons.menu)
        : null,
    key: ValueKey('$space2 $space1'),
    columns: [
      TableColumn('Name', space1),
      TableColumn('Size', space2),
      TableColumn('Last Updated', space3),
    ],
    buildRow: (row) {
      final widgets = List.generate(
        row.length,
        (index) {
          return Text(row[index],
              style: index == 0
                  ? ArDriveTypography.body.buttonNormalBold()
                  : null);
        },
      ).toList();

      return TableRowWidget(widgets);
    },
    rows: const [
      ['Thiago Carvalho', '46kb', '01/10/1998'],
      ['Karl Prieb', '1.4MB', '01/10/1998']
    ],
  );
}
