import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../components.dart';
import 'drive_list_tile.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    Key key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => ListTileTheme(
        style: ListTileStyle.drawer,
        textColor: kOnDarkSurfaceMediumEmphasis,
        iconColor: kOnDarkSurfaceMediumEmphasis,
        selectedColor: kOnDarkSurfaceHighEmphasis,
        selectedTileColor: onDarkSurfaceSelectedColor,
        child: BlocBuilder<DrivesCubit, DrivesState>(
          builder: (context, state) => Drawer(
            elevation: 1,
            child: Container(
              color: kDarkSurfaceColor,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        _buildDriveActionsButton(context, state),
                        if (state is DrivesLoadSuccess)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (state.userDrives.isNotEmpty ||
                                  state.sharedDrives.isEmpty) ...{
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    'PERSONAL DRIVES',
                                    textAlign: TextAlign.start,
                                    style: Theme.of(context)
                                        .textTheme
                                        .caption
                                        .copyWith(
                                            color: ListTileTheme.of(context)
                                                .textColor),
                                  ),
                                  trailing: _buildSyncButton(),
                                ),
                                ...state.userDrives.map(
                                  (d) => DriveListTile(
                                    drive: d,
                                    selected: state.selectedDriveId == d.id,
                                    onPressed: () => context
                                        .read<DrivesCubit>()
                                        .selectDrive(d.id),
                                  ),
                                ),
                              },
                              if (state.sharedDrives.isNotEmpty) ...{
                                ListTile(
                                  dense: true,
                                  title: Text(
                                    'SHARED DRIVES',
                                    textAlign: TextAlign.start,
                                    style: Theme.of(context)
                                        .textTheme
                                        .caption
                                        .copyWith(
                                            color: ListTileTheme.of(context)
                                                .textColor),
                                  ),
                                  trailing: state.userDrives.isEmpty
                                      ? _buildSyncButton()
                                      : null,
                                ),
                                ...state.sharedDrives.map(
                                  (d) => DriveListTile(
                                    drive: d,
                                    selected: state.selectedDriveId == d.id,
                                    onPressed: () => context
                                        .read<DrivesCubit>()
                                        .selectDrive(d.id),
                                  ),
                                ),
                              }
                            ],
                          ),
                      ],
                    ),
                  ),
                  FutureBuilder(
                    future: PackageInfo.fromPlatform(),
                    builder: (BuildContext context,
                        AsyncSnapshot<PackageInfo> snapshot) {
                      if (snapshot.hasData) {
                        return Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                'Version ${snapshot.data.version}',
                                style: Theme.of(context)
                                    .textTheme
                                    .caption
                                    .copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                        );
                      } else {
                        return Container();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _buildDriveActionsButton(
      BuildContext context, DrivesState drivesState) {
    final theme = Theme.of(context);

    return ListTileTheme(
      textColor: theme.textTheme.bodyText1.color,
      iconColor: theme.iconTheme.color,
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
                  icon: const Icon(Icons.add),
                  label: Text('NEW'),
                ),
              ),
              itemBuilder: (context) => [
                if (state is DriveDetailLoadSuccess) ...{
                  PopupMenuItem(
                    enabled: state.hasWritePermissions,
                    value: (context) => promptToCreateFolder(
                      context,
                      driveId: state.currentDrive.id,
                      parentFolderId: state.currentFolder.folder.id,
                    ),
                    child: ListTile(
                      enabled: state.hasWritePermissions,
                      title: Text('New folder'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    enabled: state.hasWritePermissions,
                    value: (context) => promptToUploadFile(
                      context,
                      driveId: state.currentDrive.id,
                      folderId: state.currentFolder.folder.id,
                      allowSelectMultiple: true,
                    ),
                    child: ListTile(
                      enabled: state.hasWritePermissions,
                      title: Text('Upload file(s)'),
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
                    value: (context) => attachDrive(context: context),
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
  }

  Widget _buildSyncButton() => BlocBuilder<SyncCubit, SyncState>(
        builder: (context, syncState) => IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => context.read<SyncCubit>().startSync(),
          tooltip: 'Sync',
        ),
      );
}
