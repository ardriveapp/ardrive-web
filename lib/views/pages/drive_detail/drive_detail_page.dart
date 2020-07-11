import 'package:drive/blocs/blocs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../partials/partials.dart';
import 'folder_view.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: BlocBuilder<DriveDetailBloc, DriveDetailState>(
            builder: (context, state) {
          return Column(
            children: <Widget>[
              if (state is FolderOpened) ...{
                _buildBreadcrumbRow(context, state.openedFolder.folder.path),
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
          );
        }),
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
            value: () {},
            child: ListTile(
              leading: Icon(Icons.library_books),
              title: Text('File upload'),
            ),
          ),
          PopupMenuItem(
            value: () {},
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
          .map(
            (s) => InkWell(
              onTap: () => context.bloc<DriveDetailBloc>().add(
                    OpenFolder(
                      folderPath:
                          '/${pathSegments.sublist(0, s.key + 1).join('/')}',
                    ),
                  ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Text('/' + s.value),
              ),
            ),
          )
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

    if (folderName.isNotEmpty)
      context.bloc<DriveDetailBloc>().add(NewFolder(folderName));
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
