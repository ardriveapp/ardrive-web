import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:file_picker_cross/file_picker_cross.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart';

import '../components.dart';
import 'drive_list_tile.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => ListTileTheme(
        style: ListTileStyle.drawer,
        textColor: kOnDarkMediumEmphasis,
        iconColor: kOnDarkMediumEmphasis,
        selectedColor: kOnDarkHighEmphasis,
        child: BlocBuilder<DrivesCubit, DrivesState>(
          builder: (context, state) => Drawer(
            elevation: 1,
            child: Container(
              color: kDarkColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDriveActionsButton(context, state),
                  if (state is DrivesLoadSuccess) ...{
                    if (state.userDrives.isNotEmpty ||
                        state.sharedDrives.isEmpty) ...{
                      ListTile(
                        dense: true,
                        title: Text(
                          'PERSONAL DRIVES',
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.caption.copyWith(
                              color: ListTileTheme.of(context).textColor),
                        ),
                        trailing: _buildSyncButton(),
                      ),
                      ...state.userDrives.map(
                        (d) => DriveListTile(
                          drive: d,
                          selected: state.selectedDriveId == d.id,
                          onPressed: () =>
                              context.bloc<DrivesCubit>().selectDrive(d.id),
                        ),
                      ),
                    },
                    if (state.sharedDrives.isNotEmpty) ...{
                      ListTile(
                        dense: true,
                        title: Text(
                          'SHARED DRIVES',
                          textAlign: TextAlign.start,
                          style: Theme.of(context).textTheme.caption.copyWith(
                              color: ListTileTheme.of(context).textColor),
                        ),
                        trailing: state.userDrives.isEmpty
                            ? _buildSyncButton()
                            : null,
                      ),
                      ...state.sharedDrives.map(
                        (d) => DriveListTile(
                          drive: d,
                          selected: state.selectedDriveId == d.id,
                          onPressed: () =>
                              context.bloc<DrivesCubit>().selectDrive(d.id),
                        ),
                      ),
                    }
                  }
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildDriveActionsButton(
          BuildContext context, DrivesState drivesState) =>
      ListTileTheme(
        textColor: kDarkColor,
        iconColor: kDarkColor,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
            child: BlocBuilder<DriveDetailCubit, DriveDetailState>(
              builder: (context, state) => PopupMenuButton<Function>(
                onSelected: (callback) => callback(context),
                child: SizedBox(
                  width: 128,
                  child: FloatingActionButton.extended(
                    onPressed: null,
                    icon: Icon(Icons.add),
                    label: Text('NEW'),
                  ),
                ),
                itemBuilder: (context) => [
                  if (state is DriveDetailLoadSuccess) ...{
                    PopupMenuItem(
                      enabled: state.hasWritePermissions,
                      value: (context) => promptToCreateFolder(
                        context,
                        targetDriveId: state.currentDrive.id,
                        targetFolderId: state.currentFolder.folder.id,
                      ),
                      child: ListTile(
                        enabled: state.hasWritePermissions,
                        title: Text('New folder'),
                      ),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      enabled: state.hasWritePermissions,
                      value: (context) => _promptToUploadFile(context),
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
                      value: (context) => promptToCreateDrive(context),
                      child: ListTile(
                        enabled: drivesState.canCreateNewDrive,
                        title: Text('New drive'),
                      ),
                    ),
                    PopupMenuItem(
                      value: (context) => _promptToAttachDrive(context),
                      child: ListTile(
                        title: Text('Attach drive'),
                      ),
                    ),
                  }
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildSyncButton() => BlocBuilder<SyncCubit, SyncState>(
        builder: (context, syncState) => syncState is SyncInProgress
            ? IconButton(
                icon: CircularProgressIndicator(
                  valueColor:
                      AlwaysStoppedAnimation<Color>(kOnDarkHighEmphasis),
                ),
                onPressed: null,
                tooltip: 'Syncing...',
              )
            : IconButton(
                icon: Icon(Icons.refresh),
                onPressed: () => context.bloc<SyncCubit>().startSync(),
                tooltip: 'Sync',
              ),
      );

  void _promptToUploadFile(BuildContext context) async {
    FilePickerCross fileChooseResult;
    try {
      fileChooseResult = await FilePickerCross.pick();
      // ignore: empty_catches
    } catch (err) {}

    if (fileChooseResult == null) return;

    context.bloc<DriveDetailCubit>().prepareFileUpload(
          FileEntity.withUserProvidedDetails(
            name: basename(fileChooseResult.path),
            size: fileChooseResult.length,
            // TODO: Replace with time reported by OS.
            lastModifiedDate: DateTime.now(),
          ),
          fileChooseResult.toUint8List(),
        );
  }

  void _promptToAttachDrive(BuildContext context) async {
    await showDialog<String>(
      context: context,
      builder: (BuildContext context) => DriveAttachForm(),
    );
  }
}
