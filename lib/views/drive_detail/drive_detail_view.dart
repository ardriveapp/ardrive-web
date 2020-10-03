import 'package:arweave/utils.dart' as utils;
import 'package:drive/blocs/blocs.dart';
import 'package:drive/components/components.dart';
import 'package:drive/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'folder_view.dart';

class DriveDetailView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return BlocListener<UploadBloc, UploadState>(
      listener: (context, state) async {
        if (state is UploadBeingPrepared) {
          await showProgressDialog(context, 'Preparing upload...');
        } else if (state is UploadFileReady) {
          Navigator.pop(context);

          var confirm = await showConfirmationDialog(
            context,
            title: 'Upload file',
            content:
                'This will cost ${utils.winstonToAr(state.uploadCost)} AR.',
            confirmingActionLabel: 'UPLOAD',
          );

          if (confirm) context.bloc<UploadBloc>().add(state.fileUploadHandle);
        } else if (state is UploadInProgress) {
          await showProgressDialog(context, 'Uploading file...');
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
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildBreadcrumbRow(
                            context,
                            state.currentDrive.name,
                            state.currentFolder.folder.path,
                          ),
                          Row(
                            children: [
                              state.currentDrive.isPrivate
                                  ? IconButton(
                                      icon: Icon(Icons.lock),
                                      onPressed: () => _showDriveInfo(context),
                                      tooltip: 'Private',
                                    )
                                  : IconButton(
                                      icon: Icon(Icons.public),
                                      onPressed: () => _showDriveInfo(context),
                                      tooltip: 'Public',
                                    ),
                              IconButton(
                                icon: Icon(Icons.info),
                                onPressed: () => _showDriveInfo(context),
                                tooltip: 'Details',
                              ),
                            ],
                          ),
                        ],
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
        TextButton(
          onPressed: () =>
              context.bloc<DriveDetailBloc>().add(FolderOpened('')),
          child: Text(driveName),
        ),
        if (pathSegments.isNotEmpty) Icon(Icons.chevron_right),
        ...pathSegments.asMap().entries.expand((s) => [
              TextButton(
                onPressed: () => context.bloc<DriveDetailBloc>().add(
                      FolderOpened(
                          '/${pathSegments.sublist(0, s.key + 1).join('/')}'),
                    ),
                child: Text(s.value),
              ),
              if (s.key < pathSegments.length - 1) Icon(Icons.chevron_right),
            ])
      ],
    );
  }

  void _showDriveInfo(BuildContext context) {
    final state = context.bloc<DriveDetailBloc>().state;

    if (state is FolderLoadSuccess) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Drive ID'),
          content: FittedBox(
            fit: BoxFit.contain,
            child: SelectableText(state.currentDrive.id, maxLines: 1),
          ),
          actions: [
            TextButton(
              child: Text('CLOSE'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );
    }
  }
}
