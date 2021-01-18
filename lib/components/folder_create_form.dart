import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
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
      builder: (_) => BlocProvider(
        create: (context) => FolderCreateCubit(
          targetDriveId: targetDriveId,
          targetFolderId: targetFolderId,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: FolderCreateForm(),
      ),
    );

class FolderCreateForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<FolderCreateCubit, FolderCreateState>(
        listener: (context, state) {
          if (state is FolderCreateInProgress) {
            showProgressDialog(context, 'CREATING FOLDER...');
          } else if (state is FolderCreateSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: 'CREATE FOLDER',
          content: SizedBox(
            width: kMediumDialogWidth,
            child: ReactiveForm(
              formGroup: context.watch<FolderCreateCubit>().form,
              child: ReactiveTextField(
                formControlName: 'name',
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Folder name'),
                showErrors: (control) => control.dirty && control.invalid,
                validationMessages: (_) => kValidationMessages,
              ),
            ),
          ),
          actions: [
            TextButton(
              child: Text('CANCEL'),
              onPressed: () => Navigator.of(context).pop(null),
            ),
            ElevatedButton(
              child: Text('CREATE'),
              onPressed: () => context.read<FolderCreateCubit>().submit(),
            ),
          ],
        ),
      );
}
