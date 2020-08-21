import 'package:arweave/utils.dart' as arweaveUtils;
import 'package:drive/blocs/blocs.dart';
import 'package:drive/views/partials/confirmation_dialog.dart';
import 'package:drive/views/partials/progress_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'folder_view.dart';

class DriveDetailPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocListener<UploadBloc, UploadState>(
      listener: (context, state) async {
        if (state is UploadBeingPrepared) {
          showProgressDialog(context, 'Preparing upload...');
        } else if (state is UploadFileReady) {
          Navigator.pop(context);

          var confirm = await showConfirmationDialog(
            context,
            title: 'Upload file',
            content:
                'This will cost ${arweaveUtils.winstonToAr(state.uploadCost)} AR.',
            confirmingActionLabel: 'UPLOAD',
          );

          if (confirm) context.bloc<UploadBloc>().add(state.fileUploadHandle);
        } else if (state is UploadInProgress) {
          showProgressDialog(context, 'Uploading file...');
        } else if (state is UploadComplete) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        body: Scrollbar(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: BlocBuilder<DriveDetailBloc, DriveDetailState>(
                builder: (context, state) => Column(
                  children: [
                    if (state is FolderLoadSuccess) ...{
                      _buildBreadcrumbRow(
                        context,
                        state.currentDrive.name,
                        state.currentFolder.folder.path,
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: FolderView(
                              subfolders: state.currentFolder.subfolders,
                              files: state.currentFolder.files,
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

  Widget _buildBreadcrumbRow(
      BuildContext context, String driveName, String path) {
    final pathSegments = path.split('/').where((s) => s != '').toList();

    return Row(
      children: [
        FlatButton(
          onPressed: () => context.bloc<DriveDetailBloc>().add(OpenFolder('')),
          child: Text(driveName),
        ),
        if (pathSegments.length > 0) Icon(Icons.chevron_right),
        ...pathSegments.asMap().entries.expand((s) => [
              FlatButton(
                onPressed: () => context.bloc<DriveDetailBloc>().add(
                      OpenFolder(
                          '/${pathSegments.sublist(0, s.key + 1).join('/')}'),
                    ),
                child: Text(s.value),
              ),
              if (s.key < pathSegments.length - 1) Icon(Icons.chevron_right),
            ])
      ],
    );
  }
}
