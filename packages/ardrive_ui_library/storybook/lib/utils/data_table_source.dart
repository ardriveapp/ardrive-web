import 'dart:math';

import 'package:flutter/material.dart';

class WidgetBookExampleDataTableSource extends DataTableSource {
  final List<int> sampleData = List.generate(256, (index) => index);
  @override
  DataRow? getRow(int index) {
    final date = DateTime.now();
    return DataRow(cells: [
      DataCell(
        Row(
          children: [
            const Padding(
              padding: EdgeInsetsDirectional.only(end: 8.0),
              child: Icon(Icons.image),
            ),
            Text('Sample ${sampleData[index]}'),
          ],
        ),
      ),
      DataCell(Text(
        Random(sampleData[index]).nextInt(1024).toString(),
        overflow: TextOverflow.ellipsis,
      )),
      DataCell(
        Text(
          '${date.year} ${date.month} ${date.day}',
          overflow: TextOverflow.ellipsis,
        ),
      )
    ]);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => sampleData.length;

  @override
  int get selectedRowCount => 0;
}
