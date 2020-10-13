import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToCreateFolder(
  BuildContext context, {
  @required String targetDriveId,
  @required String targetFolderId,
}) =>
    showDialog(
      context: context,
      builder: (_) => FolderCreateForm(
        targetDriveId: targetDriveId,
        targetFolderId: targetFolderId,
      ),
    );

class FolderCreateForm extends StatelessWidget {
  final String targetDriveId;
  final String targetFolderId;

  FolderCreateForm(
      {@required this.targetDriveId, @required this.targetFolderId});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (context) => FolderCreateCubit(
          targetDriveId: targetDriveId,
          targetFolderId: targetFolderId,
          profileBloc: context.bloc<ProfileBloc>(),
          arweave: context.repository<ArweaveService>(),
          driveDao: context.repository<DriveDao>(),
        ),
        child: BlocConsumer<FolderCreateCubit, FolderCreateState>(
          listener: (context, state) {
            if (state is FolderCreateInProgress) {
              showProgressDialog(context, 'Creating folder...');
            } else if (state is FolderCreateSuccess) {
              Navigator.pop(context);
              Navigator.pop(context);
            }
          },
          builder: (context, state) => AlertDialog(
            title: Text('Create folder'),
            content: ReactiveForm(
              formGroup: context.bloc<FolderCreateCubit>().form,
              child: ReactiveTextField(
                formControlName: 'name',
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Folder name'),
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0),
            actions: [
              TextButton(
                child: Text('CANCEL'),
                onPressed: () => Navigator.of(context).pop(null),
              ),
              TextButton(
                child: Text('CREATE'),
                onPressed: () => context.bloc<FolderCreateCubit>().submit(),
              ),
            ],
          ),
        ),
      );
}
