import 'package:drive/blocs/drive_detail/drive_detail_bloc.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FolderView extends StatelessWidget {
  final List<FolderEntry> subfolders;
  final List<FileEntry> files;

  const FolderView({
    Key key,
    @required this.subfolders,
    @required this.files,
  })  : assert(subfolders != null),
        assert(files != null),
        super(key: key);

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
        ...subfolders.map((f) => _buildFolderRow(context, f)),
        ...files.map(
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

DataRow _buildFolderRow(BuildContext context, FolderEntry folder) {
  var openFolder = () =>
      context.bloc<DriveDetailBloc>().add(OpenFolder(folderPath: folder.path));

  return DataRow(
    cells: [
      DataCell(NameCell(name: folder.name, isFolder: true), onTap: openFolder),
      DataCell(Text('me'), onTap: openFolder),
      DataCell(Text('-'), onTap: openFolder),
      DataCell(Text('-'), onTap: openFolder),
    ],
  );
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
