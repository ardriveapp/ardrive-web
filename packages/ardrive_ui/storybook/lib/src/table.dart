import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:widgetbook/widgetbook.dart';

import 'ardrive_app_base.dart';

WidgetbookCategory table() {
  return WidgetbookCategory(name: 'Table', children: [
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

  return ArDriveDataTable<File>(
    maxItemsPerPage: 100,
    rowsPerPageText: 'Rows per page',
    pageItemsDivisorFactor: 25,
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
      TableColumn('Name', space1, index: 0),
      TableColumn('Size', space2, index: 1),
      TableColumn('Last Updated', space3, index: 2, canHide: false),
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
    onChangeMultiSelecting: (isMultiSelecting) {},
    onChangePage: (page) {},
    onRowTap: (row) {},
    onSelectedRows: (rows) {},
    sortRows: (rows, columnIndex, isAscending) {
      if (columnIndex == 2) {
        return rows.sorted(compareDate);
      }

      List<File> sort(List<File> rows) {
        if (columnIndex == 0) {
          return rows.sorted(
              (a, b) => compareAlphabeticallyAndNatural(a.name, b.name));
        } else {
          return rows.sorted(
              (a, b) => compareAlphabeticallyAndNatural(a.size, b.size));
        }
      }

      return sort(rows);
    },
    forceDisableMultiSelect: false,
    lockMultiSelect: false,
    rows: [
      for (int i = 0; i < 180; i++)
        File(
          name: 'Item $i',
          size: '32.2MB',
          createdAt: DateTime(2022, 10, 22),
        ),
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

class File extends IndexedItem {
  File({
    required this.createdAt,
    required this.name,
    required this.size,
  }) : super(0);

  String name;
  DateTime createdAt;
  String size;

  @override
  List<Object?> get props => [name];
}
