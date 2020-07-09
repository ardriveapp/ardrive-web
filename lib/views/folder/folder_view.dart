import 'package:drive/repositories/repositories.dart';
import 'package:flutter/material.dart';

class FolderView extends StatelessWidget {
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  const FolderView({
    Key key,
    this.subfolders,
    this.files,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DataTable(
      columns: const <DataColumn>[
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('Owner')),
        DataColumn(label: Text('Last modified')),
        DataColumn(label: Text('File size')),
      ],
      rows: [
        ...?subfolders?.map(
          (f) => DataRow(
            cells: [
              DataCell(NameCell(name: f.name, isFolder: true)),
              DataCell(Text('me')),
              DataCell(Text('-')),
              DataCell(Text('-')),
            ],
          ),
        ),
        ...?files?.map(
          (f) => DataRow(
            cells: [
              DataCell(NameCell(name: f.name)),
              DataCell(Text('me')),
              DataCell(Text('15 January 2020')),
              DataCell(Text('27MB')),
            ],
          ),
        ),
      ],
    );
  }
}

class NameCell extends StatelessWidget {
  final String name;
  final bool isFolder;

  NameCell({this.name, this.isFolder = false});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          isFolder
              ? Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8.0),
                  child: Icon(Icons.folder),
                )
              : Padding(padding: const EdgeInsetsDirectional.only(end: 32)),
          Text(name),
        ],
      );
}
