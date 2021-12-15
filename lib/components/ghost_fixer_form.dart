import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/ghost%20fixer/ghost_fixer_cubit.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToReCreateFolder(BuildContext context,
    {required FolderEntry ghostFolder}) {
  if (ghostFolder.parentFolderId != null) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => GhostFixerCubit(
          ghostFolder: ghostFolder,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: GhostFixerForm(),
      ),
    );
  } else {
    //TODO: Fix missing root folder;
    throw UnimplementedError();
  }
}

class GhostFixerForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<GhostFixerCubit, GhostFixerState>(
        listener: (context, state) {
          if (state is GhostFixerInProgress) {
            showProgressDialog(context, 'RECREATING FOLDER...');
          } else if (state is GhostFixerSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is GhostFixerWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: 'RECREATE FOLDER',
          content: SizedBox(
            width: kMediumDialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ReactiveForm(
                  formGroup: context.watch<GhostFixerCubit>().form,
                  child: ReactiveTextField(
                    formControlName: 'name',
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Folder name'),
                    showErrors: (control) => control.dirty && control.invalid,
                    validationMessages: (_) => kValidationMessages,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => context.read<GhostFixerCubit>().submit(),
              child: Text('CREATE'),
            ),
          ],
        ),
      );
}
