import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
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
      builder: (_) => FolderRenameForm(
        driveId: driveId,
        folderId: folderId,
      ),
    );

class FolderRenameForm extends StatelessWidget {
  final String driveId;
  final String folderId;

  FolderRenameForm({@required this.driveId, @required this.folderId});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => FolderRenameCubit(
          driveId: driveId,
          folderId: folderId,
          arweave: context.repository<ArweaveService>(),
          driveDao: context.repository<DriveDao>(),
          profileBloc: context.bloc<ProfileBloc>(),
        ),
        child: BlocConsumer<FolderRenameCubit, FolderRenameState>(
          listener: (context, state) {
            if (state is FolderRenameInProgress) {
              showProgressDialog(context, 'Renaming folder...');
            } else if (state is FolderRenameSuccess) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) => AlertDialog(
            title: Text('Rename folder'),
            content: state is! FolderRenameInitializing
                ? ReactiveForm(
                    formGroup: context.bloc<FolderRenameCubit>().form,
                    child: ReactiveTextField(
                      formControlName: 'name',
                      autofocus: true,
                      decoration:
                          const InputDecoration(labelText: 'Folder name'),
                    ),
                  )
                : null,
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            actions: [
              TextButton(
                child: Text('CANCEL'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              TextButton(
                child: Text('RENAME'),
                onPressed: () => context.bloc<FolderRenameCubit>().submit(),
              ),
            ],
          ),
        ),
      );
}
