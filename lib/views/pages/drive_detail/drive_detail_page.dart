import 'dart:io';

import 'package:drive/blocs/blocs.dart';
import 'package:file_chooser/file_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart';

import '../../partials/partials.dart';
import 'folder_view.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Scrollbar(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: BlocBuilder<DriveDetailBloc, DriveDetailState>(
              builder: (context, state) => Column(
                children: <Widget>[
                  if (state is FolderOpened) ...{
                    _buildBreadcrumbRow(
                        context, state.openedFolder.folder.path),
                    Row(
                      children: [
                        Expanded(
                          child: FolderView(
                            subfolders: state.openedFolder.subfolders,
                            files: state.openedFolder.files,
                          ),
                        ),
                      ],
                    ),
                  }
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: PopupMenuButton<Function>(
        onSelected: (callback) => callback(context),
        child: FloatingActionButton(
          onPressed: null,
          child: Icon(Icons.add),
        ),
        itemBuilder: (context) => [
          PopupMenuItem(
            value: _promptToCreateNewFolder,
            child: ListTile(
              leading: Icon(Icons.create_new_folder),
              title: Text('New folder'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: _promptToUploadFile,
            child: ListTile(
              leading: Icon(Icons.add),
              title: Text('File upload'),
            ),
          ),
          PopupMenuItem(
            value: _promptToUploadFolder,
            child: ListTile(
              leading: Icon(Icons.folder),
              title: Text('Folder upload'),
            ),
          ),
          PopupMenuDivider(),
          PopupMenuItem(
            value: _promptToImportTransaction,
            child: ListTile(
              leading: Icon(Icons.import_export),
              title: Text('Import transaction'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreadcrumbRow(BuildContext context, String path) {
    final pathSegments = path.split('/').where((s) => s != '').toList();

    return Row(
      children: pathSegments
          .asMap()
          .entries
          .expand((s) => [
                FlatButton(
                  onPressed: () => context.bloc<DriveDetailBloc>().add(
                        OpenFolder(
                          folderPath:
                              '/${pathSegments.sublist(0, s.key + 1).join('/')}',
                        ),
                      ),
                  child: Text(s.value),
                ),
                if (s.key < pathSegments.length - 1) Icon(Icons.chevron_right),
              ])
          .toList(),
    );
  }

  void _promptToCreateNewFolder(BuildContext context) async {
    final folderName = await showTextFieldDialog(
      context,
      title: 'New folder',
      confirmingActionLabel: 'CREATE',
      initialText: 'Untitled folder',
    );

    if (folderName != null)
      context.bloc<DriveDetailBloc>().add(NewFolder(folderName));
  }

  void _promptToUploadFile(BuildContext context) async {
    final fileChooseResult = await showOpenPanel(
      allowsMultipleSelection: true,
    );

    if (fileChooseResult.canceled) return;

    for (final filePath in fileChooseResult.paths) {
      final file = new File(filePath);

      context.bloc<DriveDetailBloc>().add(
            UploadFile(
              basename(filePath),
              await file.length(),
              file.openRead(),
            ),
          );
    }
  }

  void _promptToUploadFolder(BuildContext context) async {
    final folderChooseResult = await showOpenPanel(
      allowsMultipleSelection: true,
      canSelectDirectories: true,
    );

    if (folderChooseResult.canceled) return;
  }

  void _promptToImportTransaction(BuildContext context) async {
    final transactionId = await showTextFieldDialog(
      context,
      title: 'Import transaction',
      confirmingActionLabel: 'IMPORT',
      fieldLabel: 'Transaction ID',
    );
  }
}
