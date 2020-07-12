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
          children: [
            _buildDriveActionsButton(context),
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
            Expanded(child: Container()),
            Divider(height: 0),
            ListTile(
              title: Text('John Applebee'),
              subtitle: Text('john@arweave.org'),
              trailing: Icon(Icons.arrow_drop_down),
              onTap: () {},
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
        padding: const EdgeInsets.all(16.0),
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
                value: _promptToUploadFolder,
                child: ListTile(
                  title: Text('Upload folder'),
                ),
              ),
              PopupMenuItem(
                value: _promptToImportTransaction,
                child: ListTile(
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
