import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToReCreateFolder(BuildContext context,
    {required OrphanParent orphanParent}) {
  if (orphanParent.parentFolderId != null) {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => OrphanFixerCubit(
          orphanParent: orphanParent,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: OrphanFixerForm(),
      ),
    );
  } else {
    return showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => RootFolderFixerCubit(
          orphanParent: orphanParent,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: RootFolderFixerForm(),
      ),
    );
  }
}

class OrphanFixerForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<OrphanFixerCubit, OrphanFixerState>(
        listener: (context, state) {
          if (state is OrphanFixerInProgress) {
            showProgressDialog(context, 'RECREATING FOLDER...');
          } else if (state is OrphanFixerSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is OrphanFixerWalletMismatch) {
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    '${context.read<OrphanFixerCubit>().orphanParent.orphans.length} orphans detected'
                    ' for missing folder with ID ${context.read<OrphanFixerCubit>().orphanParent.id}',
                  ),
                ),
                ReactiveForm(
                  formGroup: context.watch<OrphanFixerCubit>().form,
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
              onPressed: () => context.read<OrphanFixerCubit>().submit(),
              child: Text('CREATE'),
            ),
          ],
        ),
      );
}

class RootFolderFixerForm extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RootFolderFixerCubit, RootFolderFixerState>(
        listener: (context, state) {
          if (state is RootFolderFixerInProgress) {
            showProgressDialog(context, 'RECREATING ROOT FOLDER...');
          } else if (state is RootFolderFixerSuccess) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else if (state is RootFolderFixerWalletMismatch) {
            Navigator.pop(context);
          }
        },
        builder: (context, state) => AppDialog(
          title: 'RECREATE ROOT FOLDER',
          content: SizedBox(
            width: kMediumDialogWidth,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => context.read<RootFolderFixerCubit>().submit(),
              child: Text('CREATE'),
            ),
          ],
        ),
      );
}
