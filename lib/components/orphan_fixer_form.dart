import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/orphan_fixer/orphan_fixer_cubit.dart';
import 'package:ardrive/l11n/l11n.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/theme/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

import 'components.dart';

Future<void> promptToReCreateFolder(
  BuildContext context, {
  required OrphanParent orphanParent
}) =>
    showDialog(
      context: context,
      builder: (_) => BlocProvider(
        create: (context) => OrphanFixerCubit(
          driveId: orphanParent.driveId,
          parentFolderId: orphanParent.parentFolderId,
          folderId: orphanParent.id,
          profileCubit: context.read<ProfileCubit>(),
          arweave: context.read<ArweaveService>(),
          driveDao: context.read<DriveDao>(),
        ),
        child: OrphanFixerForm(),
      ),
    );

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
            child: ReactiveForm(
              formGroup: context.watch<OrphanFixerCubit>().form,
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
