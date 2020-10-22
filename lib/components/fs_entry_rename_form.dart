import 'package:ardrive/blocs/blocs.dart';
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
      builder: (_) => FsEntryRenameForm(
        driveId: driveId,
        folderId: folderId,
      ),
    );

Future<void> promptToRenameFile(
  BuildContext context, {
  @required String driveId,
  @required String fileId,
}) =>
    showDialog(
      context: context,
      builder: (_) => FsEntryRenameForm(
        driveId: driveId,
        fileId: fileId,
      ),
    );

class FsEntryRenameForm extends StatelessWidget {
  final String driveId;
  final String folderId;
  final String fileId;

  FsEntryRenameForm({@required this.driveId, this.folderId, this.fileId})
      : assert(folderId != null || fileId != null);

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => FsEntryRenameCubit(
          driveId: driveId,
          folderId: folderId,
          fileId: fileId,
          arweave: context.repository<ArweaveService>(),
          driveDao: context.repository<DriveDao>(),
          profileCubit: context.bloc<ProfileCubit>(),
        ),
        child: BlocConsumer<FsEntryRenameCubit, FsEntryRenameState>(
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
                    width: kSmallDialogWidth,
                    child: ReactiveForm(
                      formGroup: context.bloc<FsEntryRenameCubit>().form,
                      child: ReactiveTextField(
                        formControlName: 'name',
                        autofocus: true,
                        decoration: InputDecoration(
                            labelText: state.isRenamingFolder
                                ? 'Folder name'
                                : 'File name'),
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
                onPressed: () => context.bloc<FsEntryRenameCubit>().submit(),
              ),
            ],
          ),
        ),
      );
}
