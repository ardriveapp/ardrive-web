import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart';

List<DataColumn> buildTableColumns() => [
      DataColumn(label: Text('Name')),
      DataColumn(label: Text('File size')),
      DataColumn(label: Text('Last updated')),
    ];

DataRow buildFolderRow({
  @required BuildContext context,
  @required FolderEntry folder,
  bool selected = false,
  Function onPressed,
}) =>
    DataRow(
      onSelectChanged: (_) => onPressed(),
      selected: selected,
      cells: [
        DataCell(
          Row(
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 8.0),
                child: const Icon(Icons.folder),
              ),
              Text(folder.name),
            ],
          ),
        ),
        DataCell(Text('-')),
        DataCell(Text('-')),
      ],
    );

DataRow buildFileRow({
  @required BuildContext context,
  @required FileEntry file,
  bool selected = false,
  Function onPressed,
}) =>
    DataRow(
      onSelectChanged: (_) => onPressed(),
      selected: selected,
      cells: [
        DataCell(
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 32),
            child: Text(file.name),
          ),
        ),
        DataCell(Text(filesize(file.size))),
        DataCell(
          Text(
            // Show a relative timestamp if the file was updated at most 3 days ago.
            file.lastUpdated.difference(DateTime.now()).inDays > 3
                ? format(file.lastUpdated)
                : yMMdDateFormatter.format(file.lastUpdated),
          ),
        ),
      ],
    );
