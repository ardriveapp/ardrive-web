import 'dart:math';

import 'package:flutter/material.dart';

class WidgetBookExampleDataTableSource {
  final List<int> sampleData = List.generate(128, (index) => index);
  Widget? getRow(int index) {
    final date = DateTime.now();
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 8.0),
                  child: Icon(Icons.image),
                ),
                Text('Sample ${sampleData[index]}'),
              ],
            ),
          ),
        ),
        Flexible(
          child: Text(
            Random(sampleData[index]).nextInt(1024).toString(),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
          ),
        ),
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Text(
              '${date.year} ${date.month} ${date.day}',
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
            ),
          ),
        ),
      ],
    );
  }

  bool get isRowCountApproximate => false;

  int get rowCount => sampleData.length;

  int get selectedRowCount => 0;
}
