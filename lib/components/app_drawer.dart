import 'dart:convert';

import 'package:drive/blocs/blocs.dart';
import 'package:drive/repositories/repositories.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart';

import 'attach_drive_form.dart';
import 'create_new_drive_dialog.dart';
import 'text_field_dialog.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DrivesBloc, DrivesState>(
      builder: (context, state) => Drawer(
        elevation: 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 8),
            ListTile(
              dense: true,
              title:
                  Text('ArDrive', style: Theme.of(context).textTheme.headline6),
              trailing: BlocBuilder<UserBloc, UserState>(
                  builder: (context, state) => state is! UserAuthenticated
                      ? IconButton(
                          icon: Icon(Icons.login),
                          onPressed: () => _promptToLogin(context),
                          tooltip: 'Login',
                        )
                      : IconButton(
                          icon: Icon(Icons.logout),
                          onPressed: () =>
                              context.bloc<UserBloc>().add(Logout()),
                          tooltip: 'Logout',
                        )),
            ),
            _buildDriveActionsButton(state),
            BlocBuilder<SyncBloc, SyncState>(
              builder: (context, syncState) {
                final showSyncButton =
                    state is DrivesLoadSuccess && state.drives.isNotEmpty;

                return ListTile(
                  dense: true,
                  title: Text(
                    'DRIVES',
                    textAlign: TextAlign.start,
                    style: Theme.of(context).textTheme.caption,
                  ),
                  trailing: showSyncButton
                      ? (syncState is SyncInProgress
                          ? IconButton(
                              icon: CircularProgressIndicator(),
                              onPressed: null,
                              tooltip: 'Syncing...',
                            )
                          : IconButton(
                              icon: Icon(Icons.refresh),
                              onPressed: () => context
                                  .bloc<SyncBloc>()
                                  .add(SyncWithNetwork()),
                              tooltip: 'Sync',
                            ))
                      : SizedBox.shrink(child: Container()),
                );
              },
            ),
            if (state is DrivesLoadSuccess)
              ...state.drives.map(
                (d) => ListTile(
                  leading: Icon(Icons.folder_shared),
                  title: Text(d.name),
                  selected: state.selectedDriveId == d.id,
                  onTap: () =>
                      context.bloc<DrivesBloc>().add(SelectDrive(d.id)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriveActionsButton(DrivesState drivesState) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: BlocBuilder<DriveDetailBloc, DriveDetailState>(
          builder: (context, state) => PopupMenuButton<Function>(
            onSelected: (callback) => callback(context),
            child: FloatingActionButton.extended(
              onPressed: null,
              icon: Icon(Icons.add),
              label: Text('NEW'),
            ),
            itemBuilder: (context) => [
              if (state is FolderLoadSuccess) ...{
                PopupMenuItem(
                  enabled: state.hasWritePermissions,
                  value: _promptToCreateNewFolder,
                  child: ListTile(
                    enabled: state.hasWritePermissions,
                    title: Text('New folder'),
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  enabled: state.hasWritePermissions,
                  value: _promptToUploadFile,
                  child: ListTile(
                    enabled: state.hasWritePermissions,
                    title: Text('Upload file'),
                  ),
                ),
                PopupMenuDivider(),
              },
              if (drivesState is DrivesLoadSuccess) ...{
                PopupMenuItem(
                  enabled: drivesState.canCreateNewDrive,
                  value: promptToCreateNewDrive,
                  child: ListTile(
                    enabled: drivesState.canCreateNewDrive,
                    title: Text('New drive'),
                  ),
                ),
                PopupMenuItem(
                  value: _promptToAttachDrive,
                  child: ListTile(
                    title: Text('Attach drive'),
                  ),
                ),
              }
            ],
          ),
        ),
      ),
    );
  }

  void _promptToLogin(BuildContext context) async {
    var chooseResult;
    try {
      chooseResult = await FilePickerCross.pick();
      // ignore: empty_catches
    } catch (err) {}

    if (chooseResult != null && chooseResult.type != null) {
      final jwk = json.decode(chooseResult.toString());
      context.bloc<UserBloc>().add(AttemptLogin(jwk));
    }
  }

  void _promptToCreateNewFolder(BuildContext context) async {
    final folderName = await showTextFieldDialog(
      context,
      title: 'New folder',
      confirmingActionLabel: 'CREATE',
      initialText: 'Untitled folder',
    );

    if (folderName != null) {
      context.bloc<DriveDetailBloc>().add(NewFolder(folderName));
    }
  }

  void _promptToUploadFile(BuildContext context) async {
    FilePickerCross fileChooseResult;
    try {
      fileChooseResult = await FilePickerCross.pick();
      // ignore: empty_catches
    } catch (err) {}

    if (fileChooseResult == null) return;

    context.bloc<DriveDetailBloc>().add(
          UploadFile(
            FileEntity(
              name: basename(fileChooseResult.path),
              size: fileChooseResult.length,
              // TODO: Replace with time reported by OS.
              lastModifiedDate: DateTime.now(),
            ),
            fileChooseResult.toUint8List(),
          ),
        );
  }

  void _promptToAttachDrive(BuildContext context) async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AttachDriveForm(),
    );
  }
}
