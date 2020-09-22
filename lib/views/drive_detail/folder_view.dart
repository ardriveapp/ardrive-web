import 'package:drive/blocs/blocs.dart';
import 'package:drive/components/components.dart';
import 'package:drive/models/models.dart';
import 'package:filesize/filesize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

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
      showCheckboxColumn: false,
      columns: const <DataColumn>[
        DataColumn(label: Text('Name')),
        DataColumn(label: Text('File size')),
      ],
      rows: [
        ...subfolders.map((folder) => DataRow(
              onSelectChanged: (_) =>
                  context.bloc<DriveDetailBloc>().add(OpenFolder(folder.path)),
              cells: [
                DataCell(NameCell(name: folder.name, isFolder: true)),
                DataCell(Text('-')),
              ],
            )),
        ...files.map(
          (file) => DataRow(
            onSelectChanged: (_) async {
              final open = await showConfirmationDialog(context,
                  title: 'Open file?', confirmingActionLabel: 'OPEN');
              if (open != null && open) {
                await launch('https://arweave.dev/${file.dataTxId}');
              }
            },
            cells: [
              DataCell(NameCell(name: file.name)),
              DataCell(Text(filesize(file.size))),
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
