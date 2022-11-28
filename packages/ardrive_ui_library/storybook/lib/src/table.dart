import 'package:ardrive_ui_library/ardrive_ui_library.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
  
  return ArDriveTable<File>(
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
    sort: (columnIndex) {
      if (columnIndex == 2) {
        return compareDate;
      }

      int sort(File a, File b) {
        if (columnIndex == 0) {
          return compareAlphabeticallyAndNatural(a.name, b.name);
        } else {
          return compareAlphabeticallyAndNatural(a.size, b.size);
        }
      }

      return sort;
    },
    buildRow: (row) {
      final widgets = [
        Text(row.name, style: ArDriveTypography.body.buttonNormalBold()),
        Text(row.size),
        Text(DateFormat.yMMMd().format(row.createdAt))
      ];

      return TableRowWidget(widgets);
    },
    rows: [
      File(name: 'FOLDER_3081', size: '1MB', createdAt: DateTime(2022, 10, 1)),
      File(
          name: 'TUNE_3081.mp3',
          size: '3.2MB',
          createdAt: DateTime(2022, 10, 1)),
      File(
          name: 'STYLE_3081.css',
          size: '123.2MB',
          createdAt: DateTime(2022, 10, 1)),
      File(
          name: 'DOC_3081.doc',
          size: '11.2MB',
          createdAt: DateTime(2022, 10, 1)),
      File(
          name: 'MOV_3081.mp4',
          size: '14.2MB',
          createdAt: DateTime(2022, 10, 1)),
      File(name: 'APPLE.mp3', size: '1.22MB', createdAt: DateTime(2022, 10, 2)),
      File(name: 'TSLA.mp3', size: '12.2MB', createdAt: DateTime(2022, 10, 30)),
      File(name: 'NFT.png', size: '51.2MB', createdAt: DateTime(2022, 10, 10)),
      File(
          name: 'Thiagos Doc',
          size: '32.2MB',
          createdAt: DateTime(2022, 10, 1)),
      File(name: 'Karls Doc', size: '23.2MB', createdAt: DateTime(2022, 1, 10)),
      File(name: 'Archive', size: '12.2MB', createdAt: DateTime(2022, 10, 11)),
      File(
          name: 'Palmeiras', size: '32.2MB', createdAt: DateTime(2022, 10, 22)),
    ],
  );
}

/// returns -1 when `a` is before `b`
/// returns 0 when `a` is equal to `b`
/// returns 1 when `a` is after `b`
int compareAlphabeticallyAndNatural(String a, String b) {
  return compareNatural(a.toLowerCase(), b.toLowerCase());
}

int compareDate(File a, File b) {
  return a.createdAt.compareTo(b.createdAt);
}

class File {
  File({
    required this.createdAt,
    required this.name,
    required this.size,
  });

  String name;
  DateTime createdAt;
  String size;
}
