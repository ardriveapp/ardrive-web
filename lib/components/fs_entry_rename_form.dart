import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToRenameFolder(
  BuildContext context, {
  @required String driveId,
  @required String folderId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => FsEntryRenameCubit(
          driveId: driveId,
          folderId: folderId,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
        ),
        child: FsEntryRenameForm(),
      ),
    );

Future<void> promptToRenameFile(
  BuildContext context, {
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => FsEntryRenameCubit(
          driveId: driveId,
          fileId: fileId,
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
          profileCubit: context.read<ProfileCubit>(),
        ),
        child: FsEntryRenameForm(),
      ),
    );

class FsEntryRenameForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
        listener: (context, state) {
          if (state is FolderEntryRenameInProgress) {
            showProgressDialog(context, 'RENAMING FOLDER...');
          } else if (state is FileEntryRenameInProgress) {
            showProgressDialog(context, 'RENAMING FILE...');
          } else if (state is FolderEntryRenameSuccess ||
              state is FileEntryRenameSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: state.isRenamingFolder ? 'RENAME FOLDER' : 'RENAME FILE',
          content: state is! FsEntryRenameInitializing
              ? SizedBox(
                  width: kMediumDialogWidth,
                  child: ReactiveForm(
                    formGroup: context.watch<FsEntryRenameCubit>().form,
                    child: ReactiveTextField(
                      formControlName: 'name',
                      autofocus: true,
                      decoration: InputDecoration(
                          labelText: state.isRenamingFolder
                              ? 'Folder name'
                              : 'File name'),
                      showErrors: (control) => control.invalid,
                      validationMessages: (_) => kValidationMessages,
                    ),
                  ),
                )
              : null,
          actions: [
            TextButton(
              child: Text('CANCEL'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text('RENAME'),
              onPressed: () => context.read<FsEntryRenameCubit>().submit(),
            ),
          ],
        ),
      );
}
