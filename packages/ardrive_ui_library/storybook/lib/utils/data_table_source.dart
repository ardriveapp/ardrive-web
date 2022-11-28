import 'dart:math';

import 'package:flutter/material.dart';

class WidgetBookExampleDataTableSource {
  final List<int> sampleData = List.generate(128, (index) => index);
  List<List<Widget>> getRows() {
    final date = DateTime.now();

    return sampleData
        .map(
          (sampleData) => [
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 8.0),
                  child: Icon(Icons.image),
                ),
                Text('Sample $sampleData'),
              ],
            ),
            Text(
              Random(sampleData).nextInt(1024).toString(),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
            Text(
              '${date.year} ${date.month} ${date.day}',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
          ],
        )
        .toList();
  }

  bool get isRowCountApproximate => false;

  int get rowCount => sampleData.length;

  int get selectedRowCount => 0;
}
