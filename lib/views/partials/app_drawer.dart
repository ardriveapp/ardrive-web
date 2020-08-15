import 'dart:io';

import 'package:drive/blocs/blocs.dart';
import 'package:drive/views/views.dart';
import 'package:file_chooser/file_chooser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart';

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
              trailing: IconButton(
                icon: Icon(Icons.settings),
                onPressed: () {},
              ),
            ),
            _buildDriveActionsButton(context),
            ListTile(
              leading: Icon(Icons.cloud_upload),
              title: Text('Uploads'),
              onTap: () {},
            ),
            Divider(),
            BlocBuilder<SyncBloc, SyncState>(
              builder: (context, state) => ListTile(
                dense: true,
                title: Text(
                  'DRIVES',
                  textAlign: TextAlign.start,
                  style: Theme.of(context).textTheme.caption,
                ),
                trailing: state is SyncInProgress
                    ? IconButton(icon: CircularProgressIndicator())
                    : IconButton(
                        icon: Icon(Icons.refresh),
                        onPressed: () =>
                            context.bloc<SyncBloc>().add(SyncWithNetwork()),
                      ),
              ),
            ),
            if (state is DrivesReady)
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

  Widget _buildDriveActionsButton(BuildContext context) {
    final drivesState = context.bloc<DrivesBloc>().state;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: PopupMenuButton<Function>(
          onSelected: (callback) => callback(context),
          child: FloatingActionButton.extended(
            onPressed: null,
            icon: Icon(Icons.add),
            label: Text('NEW'),
          ),
          itemBuilder: (context) => [
            if (drivesState is DrivesReady &&
                drivesState.selectedDriveId != null) ...{
              PopupMenuItem(
                value: _promptToCreateNewFolder,
                child: ListTile(
                  title: Text('New folder'),
                ),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: _promptToUploadFile,
                child: ListTile(
                  title: Text('Upload file'),
                ),
              ),
              PopupMenuItem(
                enabled: false,
                value: _promptToUploadFolder,
                child: ListTile(
                  enabled: false,
                  title: Text('Upload folder'),
                ),
              ),
              PopupMenuItem(
                enabled: false,
                value: _promptToImportTransaction,
                child: ListTile(
                  enabled: false,
                  title: Text('Import transaction'),
                ),
              ),
              PopupMenuDivider(),
            },
            PopupMenuItem(
              value: promptToCreateNewDrive,
              child: ListTile(
                title: Text('New drive'),
              ),
            ),
            PopupMenuItem(
              value: null,
              child: ListTile(
                title: Text('Attach drive'),
              ),
            ),
          ],
        ),
      ),
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
              await file.readAsBytes(),
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
