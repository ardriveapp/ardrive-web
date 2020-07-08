import 'package:drive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: <Widget>[
          Row(
            children: [
              Text('Personal'),
              Icon(Icons.chevron_right),
              Text('Documents'),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: BlocProvider(
                  create: (context) => FolderBloc(),
                  child: BlocBuilder<FolderBloc, FolderState>(
                    builder: (context, state) => DataTable(
                      columns: const <DataColumn>[
                        DataColumn(label: Text('Name')),
                        DataColumn(label: Text('Owner')),
                        DataColumn(label: Text('Last modified')),
                        DataColumn(label: Text('File size')),
                      ],
                      rows: state is FolderLoadSuccess
                          ? [
                              ...state.subfolders.map(
                                (f) => DataRow(
                                  cells: [
                                    DataCell(
                                        NameCell(name: f.name, isFolder: true)),
                                    DataCell(Text('me')),
                                    DataCell(Text('-')),
                                    DataCell(Text('-')),
                                  ],
                                ),
                              ),
                              ...state.files.map(
                                (f) => DataRow(
                                  cells: [
                                    DataCell(NameCell(name: f.name)),
                                    DataCell(Text('me')),
                                    DataCell(Text('15 January 2020')),
                                    DataCell(Text('27MB')),
                                  ],
                                ),
                              ),
                            ]
                          : [],
                    ),
                  ),
                ),
              ),
            ],
          )
        ],
      ),
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
