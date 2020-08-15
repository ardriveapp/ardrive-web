import 'package:drive/blocs/blocs.dart';
import 'package:drive/views/partials/confirmation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'folder_view.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocListener<UploadBloc, UploadState>(
      listener: (context, state) async {
        if (state is FileUploadReady) {
          var confirm = await showConfirmationDialog(
            context,
            title: 'Upload file',
            content: 'This will cost ${state.uploadCost} AR.',
            confirmingActionLabel: 'UPLOAD',
          );

          if (confirm) context.bloc<UploadBloc>().add(state.fileUploadHandle);
        }
      },
      child: Scaffold(
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
}
