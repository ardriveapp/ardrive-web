import 'package:ardrive/models/models.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';

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
                child: Icon(Icons.folder),
              ),
              Text(folder.name),
            ],
          ),
        ),
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
      ],
    );
