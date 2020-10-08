import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/components.dart';
import 'package:ardrive/components/folder_rename_form.dart';
import 'package:ardrive/models/models.dart';
import 'package:arweave/utils.dart' as utils;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'components/table_rows.dart';

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
      child: SizedBox.expand(
        child: Scrollbar(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
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
                              if (state.selectedItemId != null &&
                                  state.hasWritePermissions) ...{
                                if (!state.selectedItemIsFolder)
                                  IconButton(
                                    icon: Icon(Icons.file_download),
                                    onPressed: () {},
                                    tooltip: 'Download',
                                  ),
                                IconButton(
                                  icon: Icon(Icons.drive_file_rename_outline),
                                  onPressed: () {
                                    if (state.selectedItemIsFolder) {
                                      promptToRenameFolder(context,
                                          folderId: state.selectedItemId);
                                    } else {
                                      promptToRenameFile(context,
                                          fileId: state.selectedItemId);
                                    }
                                  },
                                  tooltip: 'Rename',
                                ),
                                IconButton(
                                  icon: Icon(Icons.drive_file_move),
                                  onPressed: () {},
                                  tooltip: 'Move',
                                ),
                                Container(height: 32, child: VerticalDivider()),
                              },
                              if (!state.hasWritePermissions)
                                IconButton(
                                  icon: Icon(Icons.remove_red_eye),
                                  onPressed: () => _showDriveInfo(context),
                                  tooltip: 'View Only',
                                ),
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
                                tooltip: 'View Info',
                              ),
                            ],
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: DataTable(
                              showCheckboxColumn: false,
                              columns: const <DataColumn>[
                                DataColumn(label: Text('Name')),
                                DataColumn(label: Text('File size')),
                              ],
                              rows: [
                                ...state.currentFolder.subfolders.map(
                                  (folder) => buildFolderRow(
                                    context: context,
                                    folder: folder,
                                    selected: folder.id == state.selectedItemId,
                                    onPressed: () {
                                      final bloc =
                                          context.bloc<DriveDetailCubit>();
                                      if (folder.id == state.selectedItemId) {
                                        bloc.openFolderAtPath(folder.path);
                                      } else {
                                        bloc.selectItem(
                                          folder.id,
                                          isFolder: true,
                                        );
                                      }
                                    },
                                  ),
                                ),
                                ...state.currentFolder.files.map(
                                  (file) => buildFileRow(
                                    context: context,
                                    file: file,
                                    selected: file.id == state.selectedItemId,
                                    onPressed: () {
                                      final bloc =
                                          context.bloc<DriveDetailCubit>();
                                      if (file.id == state.selectedItemId) {
                                      } else {
                                        bloc.selectItem(file.id);
                                      }
                                    },
                                  ),
                                ),
                              ],
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
              context.bloc<DriveDetailCubit>().openFolderAtPath(''),
          child: Text(driveName),
        ),
        if (pathSegments.isNotEmpty) Icon(Icons.chevron_right),
        ...pathSegments.asMap().entries.expand((s) => [
              TextButton(
                onPressed: () => context
                    .bloc<DriveDetailCubit>()
                    .openFolderAtPath(
                        '/${pathSegments.sublist(0, s.key + 1).join('/')}'),
                child: Text(s.value),
              ),
              if (s.key < pathSegments.length - 1) Icon(Icons.chevron_right),
            ])
      ],
    );
  }

  void _showDriveInfo(BuildContext context) {
    final state = context.bloc<DriveDetailCubit>().state;

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
